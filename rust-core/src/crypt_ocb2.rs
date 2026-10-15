use aes::cipher::{BlockDecrypt, BlockEncrypt, KeyInit, generic_array::GenericArray};
use aes::Aes128;

#[derive(Debug, PartialEq, Eq, Clone, Copy)]
pub enum CryptError {
    PacketTooShort,
    BufferTooSmall,
    InvalidIV,
    ReplayOrDesync,
    ReplayDetected,
    TagMismatch,
}

impl std::fmt::Display for CryptError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{:?}", self)
    }
}

impl std::error::Error for CryptError {}

pub struct CryptStateOCB2 {
    #[allow(dead_code)]
    raw_key: [u8; 16],
    encrypt_iv: [u8; 16],
    decrypt_iv: [u8; 16],
    decrypt_history: [u8; 256],
    cipher: Aes128,
}

impl CryptStateOCB2 {
    pub fn new(key: &[u8], encrypt_iv: &[u8], decrypt_iv: &[u8]) -> Self {
        assert_eq!(key.len(), 16, "Key must be 16 bytes for AES-128");
        assert_eq!(encrypt_iv.len(), 16, "Encrypt IV must be 16 bytes");
        assert_eq!(decrypt_iv.len(), 16, "Decrypt IV must be 16 bytes");

        let mut rkey = [0u8; 16];
        let mut eiv = [0u8; 16];
        let mut div = [0u8; 16];
        rkey.copy_from_slice(key);
        eiv.copy_from_slice(encrypt_iv);
        div.copy_from_slice(decrypt_iv);

        let cipher = Aes128::new(GenericArray::from_slice(&rkey));

        Self {
            raw_key: rkey,
            encrypt_iv: eiv,
            decrypt_iv: div,
            decrypt_history: [0u8; 256],
            cipher,
        }
    }

    pub fn encrypt(&mut self, src: &[u8], dst: &mut [u8]) -> Result<usize, CryptError> {
        let plain_len = src.len();
        let crypted_len = plain_len + 4;
        if dst.len() < crypted_len {
            return Err(CryptError::BufferTooSmall);
        }

        // Increment encrypt_iv like a 128-bit little-endian counter
        for i in 0..16 {
            self.encrypt_iv[i] = self.encrypt_iv[i].wrapping_add(1);
            if self.encrypt_iv[i] != 0 {
                break;
            }
        }

        let mut tag = [0u8; 16];
        ocb_encrypt(
            &self.cipher,
            src,
            &mut dst[4..crypted_len],
            &self.encrypt_iv,
            &mut tag,
        );

        dst[0] = self.encrypt_iv[0];
        dst[1] = tag[0];
        dst[2] = tag[1];
        dst[3] = tag[2];

        Ok(crypted_len)
    }

    pub fn decrypt(&mut self, src: &[u8], dst: &mut [u8]) -> Result<usize, CryptError> {
        if src.len() < 4 {
            return Err(CryptError::PacketTooShort);
        }
        let plain_len = src.len() - 4;
        if dst.len() < plain_len {
            return Err(CryptError::BufferTooSmall);
        }

        let ivbyte = src[0];
        let save_iv = self.decrypt_iv;
        let mut restore = false;

        if self.decrypt_iv[0].wrapping_add(1) == ivbyte {
            // In order
            if ivbyte > self.decrypt_iv[0] {
                self.decrypt_iv[0] = ivbyte;
            } else if ivbyte < self.decrypt_iv[0] {
                self.decrypt_iv[0] = ivbyte;
                for i in 1..16 {
                    self.decrypt_iv[i] = self.decrypt_iv[i].wrapping_add(1);
                    if self.decrypt_iv[i] != 0 {
                        break;
                    }
                }
            } else {
                return Err(CryptError::InvalidIV);
            }
        } else {
            // Out of order or repeat
            let mut diff = (ivbyte as i32) - (self.decrypt_iv[0] as i32);
            if diff > 128 {
                diff -= 256;
            } else if diff < -128 {
                diff += 256;
            }

            if ivbyte < self.decrypt_iv[0] && diff > -30 && diff < 0 {
                // Late packet, no wraparound
                self.decrypt_iv[0] = ivbyte;
                restore = true;
            } else if ivbyte > self.decrypt_iv[0] && diff > -30 && diff < 0 {
                // Last was e.g. 0x02, here comes 0xff from last round
                self.decrypt_iv[0] = ivbyte;
                for i in 1..16 {
                    let prev = self.decrypt_iv[i];
                    self.decrypt_iv[i] = self.decrypt_iv[i].wrapping_sub(1);
                    if prev != 0 {
                        break;
                    }
                }
                restore = true;
            } else if ivbyte > self.decrypt_iv[0] && diff > 0 {
                // Lost a few packets, no wraparound
                self.decrypt_iv[0] = ivbyte;
            } else if ivbyte < self.decrypt_iv[0] && diff > 0 {
                // Lost packets with wraparound
                self.decrypt_iv[0] = ivbyte;
                for i in 1..16 {
                    self.decrypt_iv[i] = self.decrypt_iv[i].wrapping_add(1);
                    if self.decrypt_iv[i] != 0 {
                        break;
                    }
                }
            } else {
                return Err(CryptError::ReplayOrDesync);
            }

            if self.decrypt_history[self.decrypt_iv[0] as usize] == self.decrypt_iv[1] {
                self.decrypt_iv = save_iv;
                return Err(CryptError::ReplayDetected);
            }
        }

        let mut tag = [0u8; 16];
        ocb_decrypt(
            &self.cipher,
            &src[4..],
            &mut dst[..plain_len],
            &self.decrypt_iv,
            &mut tag,
        );

        if tag[0..3] != src[1..4] {
            self.decrypt_iv = save_iv;
            return Err(CryptError::TagMismatch);
        }

        self.decrypt_history[self.decrypt_iv[0] as usize] = self.decrypt_iv[1];
        if restore {
            self.decrypt_iv = save_iv;
        }

        Ok(plain_len)
    }
}

// AES block encryption helper
fn aes_encrypt_block(cipher: &Aes128, block: &mut [u8; 16]) {
    let ga = GenericArray::from_mut_slice(block);
    cipher.encrypt_block(ga);
}

// AES block decryption helper
fn aes_decrypt_block(cipher: &Aes128, block: &mut [u8; 16]) {
    let ga = GenericArray::from_mut_slice(block);
    cipher.decrypt_block(ga);
}

// GF(2^128) doubling S2(block)
fn s2(block: &mut [u8; 16]) {
    let b0 = u64::from_be_bytes(block[0..8].try_into().unwrap());
    let b1 = u64::from_be_bytes(block[8..16].try_into().unwrap());
    let carry = (b0 >> 63) as u64;

    let new_b0 = (b0 << 1) | (b1 >> 63);
    let new_b1 = (b1 << 1) ^ (carry * 0x87);

    block[0..8].copy_from_slice(&new_b0.to_be_bytes());
    block[8..16].copy_from_slice(&new_b1.to_be_bytes());
}

// S3(block) = block ^ S2(block)
fn s3(block: &mut [u8; 16]) {
    let mut s2_block = *block;
    s2(&mut s2_block);
    for i in 0..16 {
        block[i] ^= s2_block[i];
    }
}

fn ocb_encrypt(
    cipher: &Aes128,
    plain: &[u8],
    encrypted: &mut [u8],
    nonce: &[u8; 16],
    tag: &mut [u8; 16],
) {
    let mut delta = *nonce;
    aes_encrypt_block(cipher, &mut delta);
    let mut checksum = [0u8; 16];

    let mut offset = 0;
    let mut remaining = plain.len();

    while remaining > 16 {
        s2(&mut delta);
        let mut tmp = [0u8; 16];
        for i in 0..16 {
            tmp[i] = delta[i] ^ plain[offset + i];
        }
        aes_encrypt_block(cipher, &mut tmp);
        for i in 0..16 {
            encrypted[offset + i] = delta[i] ^ tmp[i];
            checksum[i] ^= plain[offset + i];
        }
        remaining -= 16;
        offset += 16;
    }

    s2(&mut delta);
    let mut tmp = [0u8; 16];
    let len_bits = (remaining as u64) * 8;
    tmp[8..16].copy_from_slice(&len_bits.to_be_bytes());
    for i in 0..16 {
        tmp[i] ^= delta[i];
    }
    let mut pad = tmp;
    aes_encrypt_block(cipher, &mut pad);

    let mut tmp2 = [0u8; 16];
    tmp2[..remaining].copy_from_slice(&plain[offset..offset + remaining]);
    tmp2[remaining..].copy_from_slice(&pad[remaining..]);

    for i in 0..16 {
        checksum[i] ^= tmp2[i];
        tmp2[i] ^= pad[i];
    }
    encrypted[offset..offset + remaining].copy_from_slice(&tmp2[..remaining]);

    s3(&mut delta);
    for i in 0..16 {
        tmp[i] = delta[i] ^ checksum[i];
    }
    aes_encrypt_block(cipher, &mut tmp);
    tag.copy_from_slice(&tmp);
}

fn ocb_decrypt(
    cipher: &Aes128,
    encrypted: &[u8],
    plain: &mut [u8],
    nonce: &[u8; 16],
    tag: &mut [u8; 16],
) {
    let mut delta = *nonce;
    aes_encrypt_block(cipher, &mut delta);
    let mut checksum = [0u8; 16];

    let mut offset = 0;
    let mut remaining = encrypted.len();

    while remaining > 16 {
        s2(&mut delta);
        let mut tmp = [0u8; 16];
        for i in 0..16 {
            tmp[i] = delta[i] ^ encrypted[offset + i];
        }
        aes_decrypt_block(cipher, &mut tmp);
        for i in 0..16 {
            plain[offset + i] = delta[i] ^ tmp[i];
            checksum[i] ^= plain[offset + i];
        }
        remaining -= 16;
        offset += 16;
    }

    s2(&mut delta);
    let mut tmp = [0u8; 16];
    let len_bits = (remaining as u64) * 8;
    tmp[8..16].copy_from_slice(&len_bits.to_be_bytes());
    for i in 0..16 {
        tmp[i] ^= delta[i];
    }
    let mut pad = tmp;
    aes_encrypt_block(cipher, &mut pad);

    let mut tmp2 = [0u8; 16];
    tmp2[..remaining].copy_from_slice(&encrypted[offset..offset + remaining]);
    for i in 0..16 {
        tmp2[i] ^= pad[i];
        checksum[i] ^= tmp2[i];
    }
    plain[offset..offset + remaining].copy_from_slice(&tmp2[..remaining]);

    s3(&mut delta);
    for i in 0..16 {
        tmp[i] = delta[i] ^ checksum[i];
    }
    aes_encrypt_block(cipher, &mut tmp);
    tag.copy_from_slice(&tmp);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_ocb2_encrypt_decrypt_roundtrip() {
        let key = b"0123456789abcdef";
        let client_nonce = [1u8; 16];
        let server_nonce = [2u8; 16];

        let mut client_crypt = CryptStateOCB2::new(key, &client_nonce, &server_nonce);
        // Server's decrypt_iv is client's encrypt_iv
        let mut server_crypt = CryptStateOCB2::new(key, &server_nonce, &client_nonce);

        let test_payloads: Vec<Vec<u8>> = vec![
            b"Hello".to_vec(),
            b"16_bytes_block_!".to_vec(),
            b"This is a longer payload exceeding AES block size 16 bytes easily.".to_vec(),
            vec![42u8; 256],
        ];

        for payload in test_payloads {
            let mut crypted = vec![0u8; payload.len() + 4];
            let crypted_len = client_crypt.encrypt(&payload, &mut crypted).unwrap();
            assert_eq!(crypted_len, payload.len() + 4);

            let mut decrypted = vec![0u8; payload.len()];
            let decrypted_len = server_crypt.decrypt(&crypted[..crypted_len], &mut decrypted).unwrap();
            assert_eq!(decrypted_len, payload.len());
            assert_eq!(decrypted, payload);
        }
    }

    #[test]
    fn test_ocb2_tampered_tag_fails() {
        let key = b"0123456789abcdef";
        let nonce = [0u8; 16];
        let mut crypt1 = CryptStateOCB2::new(key, &nonce, &nonce);
        let mut crypt2 = CryptStateOCB2::new(key, &nonce, &nonce);

        let plain = b"Test message";
        let mut crypted = vec![0u8; plain.len() + 4];
        crypt1.encrypt(plain, &mut crypted).unwrap();

        // Tamper with tag
        crypted[1] ^= 0x55;

        let mut decrypted = vec![0u8; plain.len()];
        let res = crypt2.decrypt(&crypted, &mut decrypted);
        assert_eq!(res, Err(CryptError::TagMismatch));
    }

    #[test]
    fn test_ocb2_replay_fails() {
        let key = b"0123456789abcdef";
        let nonce = [0u8; 16];
        let mut crypt1 = CryptStateOCB2::new(key, &nonce, &nonce);
        let mut crypt2 = CryptStateOCB2::new(key, &nonce, &nonce);

        let plain = b"Test replay";
        let mut crypted = vec![0u8; plain.len() + 4];
        crypt1.encrypt(plain, &mut crypted).unwrap();

        let mut decrypted = vec![0u8; plain.len()];
        // First decrypt succeeds
        assert!(crypt2.decrypt(&crypted, &mut decrypted).is_ok());

        // Replaying the exact same packet must fail
        let replay_res = crypt2.decrypt(&crypted, &mut decrypted);
        assert_eq!(replay_res, Err(CryptError::ReplayOrDesync));
    }
}

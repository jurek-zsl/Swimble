use rcgen::{CertificateParams, DnType, KeyPair};
use crate::MumbleError;
use base64::Engine;

#[derive(uniffi::Record, Clone, Debug, PartialEq)]
pub struct ClientIdentity {
    pub cert_pem: String,
    pub key_pem: String,
}

#[uniffi::export]
pub fn generate_client_identity(common_name: String) -> ClientIdentity {
    let mut params = CertificateParams::new(vec![common_name.clone()]).unwrap_or_default();
    params.distinguished_name.push(DnType::CommonName, common_name);
    let key_pair = KeyPair::generate().expect("Failed to generate client key pair");
    let cert = params
        .self_signed(&key_pair)
        .expect("Failed to generate client certificate");

    ClientIdentity {
        cert_pem: cert.pem(),
        key_pem: key_pair.serialize_pem(),
    }
}

pub fn pem_to_der(pem: &str) -> Result<Vec<u8>, MumbleError> {
    let clean: String = pem
        .lines()
        .filter(|l| !l.starts_with("-----") && !l.trim().is_empty())
        .collect();
    base64::engine::general_purpose::STANDARD
        .decode(clean.trim())
        .map_err(|e| MumbleError::CertificateError(format!("Invalid base64 in PEM: {}", e)))
}

pub fn der_to_pem(tag: &str, der: &[u8]) -> String {
    let b64 = base64::engine::general_purpose::STANDARD.encode(der);
    let mut out = format!("-----BEGIN {}-----\n", tag);
    for chunk in b64.as_bytes().chunks(64) {
        if let Ok(s) = std::str::from_utf8(chunk) {
            out.push_str(s);
            out.push('\n');
        }
    }
    out.push_str(&format!("-----END {}-----\n", tag));
    out
}

#[uniffi::export]
fn export_pkcs12_via_openssl(
    cert_pem: &str,
    key_pem: &str,
    password: &str,
) -> Result<Vec<u8>, MumbleError> {
    use std::io::Write;
    use std::process::Command;

    let mut cert_file = tempfile::Builder::new()
        .prefix("swimble_cert_")
        .suffix(".pem")
        .tempfile()
        .map_err(|e| MumbleError::CertificateError(format!("Tempfile error: {}", e)))?;
    cert_file
        .write_all(cert_pem.as_bytes())
        .map_err(|e| MumbleError::CertificateError(format!("Failed to write cert: {}", e)))?;

    let mut key_file = tempfile::Builder::new()
        .prefix("swimble_key_")
        .suffix(".pem")
        .tempfile()
        .map_err(|e| MumbleError::CertificateError(format!("Tempfile error: {}", e)))?;
    key_file
        .write_all(key_pem.as_bytes())
        .map_err(|e| MumbleError::CertificateError(format!("Failed to write key: {}", e)))?;

    let out_file = tempfile::Builder::new()
        .prefix("swimble_export_")
        .suffix(".p12")
        .tempfile()
        .map_err(|e| MumbleError::CertificateError(format!("Tempfile error: {}", e)))?;

    let openssl_bin = if std::path::Path::new("/opt/homebrew/bin/openssl").exists() {
        "/opt/homebrew/bin/openssl"
    } else {
        "/usr/bin/openssl"
    };

    let status = Command::new(openssl_bin)
        .args([
            "pkcs12",
            "-export",
            "-in",
            cert_file.path().to_str().unwrap_or(""),
            "-inkey",
            key_file.path().to_str().unwrap_or(""),
            "-out",
            out_file.path().to_str().unwrap_or(""),
            "-certpbe",
            "PBE-SHA1-3DES",
            "-keypbe",
            "PBE-SHA1-3DES",
            "-passout",
            &format!("pass:{}", password),
        ])
        .output()
        .map_err(|e| MumbleError::CertificateError(format!("Failed to run openssl: {}", e)))?;

    if status.status.success() {
        let bytes = std::fs::read(out_file.path())
            .map_err(|e| MumbleError::CertificateError(format!("Failed to read exported p12: {}", e)))?;
        Ok(bytes)
    } else {
        let err = String::from_utf8_lossy(&status.stderr);
        Err(MumbleError::CertificateError(format!("OpenSSL export failed: {}", err)))
    }
}

fn import_pkcs12_via_openssl(
    p12_bytes: &[u8],
    password: &str,
) -> Result<ClientIdentity, MumbleError> {
    use std::io::Write;
    use std::process::Command;

    let mut temp = tempfile::Builder::new()
        .prefix("swimble_import_")
        .suffix(".p12")
        .tempfile()
        .map_err(|e| MumbleError::CertificateError(format!("Tempfile error: {}", e)))?;
    temp.write_all(p12_bytes)
        .map_err(|e| MumbleError::CertificateError(format!("Failed to write p12 tempfile: {}", e)))?;

    let openssl_bin = if std::path::Path::new("/opt/homebrew/bin/openssl").exists() {
        "/opt/homebrew/bin/openssl"
    } else {
        "/usr/bin/openssl"
    };

    let output = Command::new(openssl_bin)
        .args([
            "pkcs12",
            "-in",
            temp.path().to_str().unwrap_or(""),
            "-nodes",
            "-passin",
            &format!("pass:{}", password),
        ])
        .output()
        .map_err(|e| MumbleError::CertificateError(format!("OpenSSL execution error: {}", e)))?;

    if !output.status.success() {
        let err = String::from_utf8_lossy(&output.stderr);
        return Err(MumbleError::CertificateError(format!("OpenSSL import failed: {}", err)));
    }

    let stdout = String::from_utf8_lossy(&output.stdout);
    extract_cert_and_key_pem(&stdout)
}

fn extract_cert_and_key_pem(pem_bundle: &str) -> Result<ClientIdentity, MumbleError> {
    let mut cert_pem = String::new();
    let mut key_pem = String::new();

    let mut in_cert = false;
    let mut in_key = false;

    for line in pem_bundle.lines() {
        if line.contains("BEGIN CERTIFICATE") {
            in_cert = true;
            cert_pem.push_str(line);
            cert_pem.push('\n');
        } else if line.contains("END CERTIFICATE") {
            cert_pem.push_str(line);
            cert_pem.push('\n');
            in_cert = false;
        } else if in_cert {
            cert_pem.push_str(line);
            cert_pem.push('\n');
        } else if line.contains("BEGIN PRIVATE KEY")
            || line.contains("BEGIN RSA PRIVATE KEY")
            || line.contains("BEGIN EC PRIVATE KEY")
        {
            in_key = true;
            key_pem.push_str(line);
            key_pem.push('\n');
        } else if line.contains("END PRIVATE KEY")
            || line.contains("END RSA PRIVATE KEY")
            || line.contains("END EC PRIVATE KEY")
        {
            key_pem.push_str(line);
            key_pem.push('\n');
            in_key = false;
        } else if in_key {
            key_pem.push_str(line);
            key_pem.push('\n');
        }
    }

    if cert_pem.is_empty() || key_pem.is_empty() {
        return Err(MumbleError::CertificateError(
            "Could not find both certificate and private key in bundle".into(),
        ));
    }

    Ok(ClientIdentity { cert_pem, key_pem })
}

#[uniffi::export]
pub fn export_identity_to_pkcs12(
    cert_pem: String,
    key_pem: String,
    password: String,
) -> Result<Vec<u8>, MumbleError> {
    // 1. Try standard OpenSSL/LibreSSL tool (produces PBE-SHA1-3DES compatible with OpenSSL 3/4, LibreSSL, Mumble, and macOS)
    if let Ok(bytes) = export_pkcs12_via_openssl(&cert_pem, &key_pem, &password) {
        return Ok(bytes);
    }

    // 2. Fall back to pure-Rust p12 crate
    let cert_der = pem_to_der(&cert_pem)?;
    let key_der = pem_to_der(&key_pem)?;
    let pfx = p12::PFX::new(&cert_der, &key_der, None, &password, "Swimble Identity")
        .ok_or_else(|| MumbleError::CertificateError("Failed to construct PKCS#12 bundle".into()))?;
    Ok(pfx.to_der())
}

#[uniffi::export]
pub fn import_identity_from_pkcs12(
    p12_bytes: Vec<u8>,
    password: String,
) -> Result<ClientIdentity, MumbleError> {
    // 1. Try modern pure-Rust parser (ribergshamra-pkcs12, supports PBES2 AES-256 + 3DES as used by OpenSSL 3/4 & Mumble)
    if let Ok(parsed) = ribergshamra_pkcs12::parse_pkcs12(&p12_bytes, &password) {
        if let (Some(cert_der), Some(key_der)) = (parsed.certificates.first(), parsed.private_keys.first()) {
            return Ok(ClientIdentity {
                cert_pem: der_to_pem("CERTIFICATE", cert_der),
                key_pem: der_to_pem("PRIVATE KEY", key_der.as_ref()),
            });
        }
    }

    // If password was non-empty and failed, also try empty string in case the file wasn't encrypted with password
    if !password.is_empty() {
        if let Ok(parsed) = ribergshamra_pkcs12::parse_pkcs12(&p12_bytes, "") {
            if let (Some(cert_der), Some(key_der)) = (parsed.certificates.first(), parsed.private_keys.first()) {
                return Ok(ClientIdentity {
                    cert_pem: der_to_pem("CERTIFICATE", cert_der),
                    key_pem: der_to_pem("PRIVATE KEY", key_der.as_ref()),
                });
            }
        }
    }

    // 2. Try legacy p12 crate parser (supporting 40-bit RC2 and 3DES)
    if let Ok(pfx) = p12::PFX::parse(&p12_bytes) {
        let certs = pfx.cert_x509_bags(&password).or_else(|_| pfx.cert_x509_bags(""));
        let keys = pfx.key_bags(&password).or_else(|_| pfx.key_bags(""));

        if let (Ok(certs), Ok(keys)) = (certs, keys) {
            if let (Some(cert_der), Some(key_der)) = (certs.into_iter().next(), keys.into_iter().next()) {
                return Ok(ClientIdentity {
                    cert_pem: der_to_pem("CERTIFICATE", &cert_der),
                    key_pem: der_to_pem("PRIVATE KEY", &key_der),
                });
            }
        }
    }

    // 3. Fall back to system OpenSSL / LibreSSL
    if let Ok(identity) = import_pkcs12_via_openssl(&p12_bytes, &password) {
        return Ok(identity);
    }
    if !password.is_empty() {
        if let Ok(identity) = import_pkcs12_via_openssl(&p12_bytes, "") {
            return Ok(identity);
        }
    }

    Err(MumbleError::CertificateError(
        "No private key or certificate found in PKCS#12 bundle. Please check that the password is correct.".into(),
    ))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_pkcs12_export_import_roundtrip() {
        let identity = generate_client_identity("Swimble Test User".to_string());
        let password = "TestPassword123!".to_string();

        let p12_bytes = export_identity_to_pkcs12(
            identity.cert_pem.clone(),
            identity.key_pem.clone(),
            password.clone(),
        ).expect("Export failed");
        assert!(!p12_bytes.is_empty());

        let imported = import_identity_from_pkcs12(p12_bytes, password)
            .expect("Import failed");

        assert!(!imported.cert_pem.is_empty());
        assert!(!imported.key_pem.is_empty());
        assert_eq!(pem_to_der(&identity.cert_pem).unwrap(), pem_to_der(&imported.cert_pem).unwrap());
        assert_eq!(pem_to_der(&identity.key_pem).unwrap(), pem_to_der(&imported.key_pem).unwrap());
    }

    #[test]
    fn test_pkcs12_empty_password_roundtrip() {
        let identity = generate_client_identity("NoPassword User".to_string());
        let password = "".to_string();

        let p12_bytes = export_identity_to_pkcs12(
            identity.cert_pem.clone(),
            identity.key_pem.clone(),
            password.clone(),
        ).expect("Export failed");

        let imported = import_identity_from_pkcs12(p12_bytes.clone(), password)
            .expect("Import failed");

        std::fs::write("/tmp/swimble_export.p12", &p12_bytes).unwrap();
        assert_eq!(pem_to_der(&identity.cert_pem).unwrap(), pem_to_der(&imported.cert_pem).unwrap());
    }

    #[test]
    fn test_parse_mumble_openssl_p12() {
        if let Ok(bytes) = std::fs::read("/tmp/test_mumble.p12") {
            let parsed = ribergshamra_pkcs12::parse_pkcs12(&bytes, "")
                .expect("Failed to parse OpenSSL modern PKCS#12");
            assert!(!parsed.certificates.is_empty());
            assert!(!parsed.private_keys.is_empty());
        }
        if let Ok(bytes) = std::fs::read("/tmp/test_mumble_pw.p12") {
            let parsed = ribergshamra_pkcs12::parse_pkcs12(&bytes, "Secret123!")
                .expect("Failed to parse password-protected OpenSSL modern PKCS#12");
            assert!(!parsed.certificates.is_empty());
            assert!(!parsed.private_keys.is_empty());
        }
    }
}

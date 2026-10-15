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
pub fn export_identity_to_pkcs12(
    cert_pem: String,
    key_pem: String,
    password: String,
) -> Result<Vec<u8>, MumbleError> {
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
    let pfx = p12::PFX::parse(&p12_bytes)
        .map_err(|e| MumbleError::CertificateError(format!("Failed to parse PKCS#12: {:?}", e)))?;
    let certs = pfx.cert_x509_bags(&password)
        .map_err(|e| MumbleError::CertificateError(format!("Failed to extract certificate from PKCS#12: {:?}", e)))?;
    let keys = pfx.key_bags(&password)
        .map_err(|e| MumbleError::CertificateError(format!("Failed to extract private key from PKCS#12: {:?}", e)))?;

    let cert_der = certs.into_iter().next()
        .ok_or_else(|| MumbleError::CertificateError("No certificate found in PKCS#12 bundle".into()))?;
    let key_der = keys.into_iter().next()
        .ok_or_else(|| MumbleError::CertificateError("No private key found in PKCS#12 bundle".into()))?;

    Ok(ClientIdentity {
        cert_pem: der_to_pem("CERTIFICATE", &cert_der),
        key_pem: der_to_pem("PRIVATE KEY", &key_der),
    })
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

        let imported = import_identity_from_pkcs12(p12_bytes, password)
            .expect("Import failed");

        assert_eq!(pem_to_der(&identity.cert_pem).unwrap(), pem_to_der(&imported.cert_pem).unwrap());
    }
}

use rustls::client::danger::{HandshakeSignatureValid, ServerCertVerified, ServerCertVerifier};
use rustls::pki_types::pem::PemObject;
use rustls::pki_types::{CertificateDer, PrivateKeyDer, ServerName, UnixTime};
use rustls::{DigitallySignedStruct, Error as RustlsError, SignatureScheme};
use std::sync::Arc;
use tokio::net::TcpStream;
use tokio_rustls::client::TlsStream;
use tokio_rustls::TlsConnector;

/// An explicit pin is scoped to the original host and port by the caller. A pin
/// replaces PKI validation for private servers, but never handshake signatures.
#[derive(Debug)]
pub struct ServerIdentityVerifier {
    platform: rustls_platform_verifier::Verifier,
    pin: Option<String>,
    failure: Arc<std::sync::Mutex<Option<crate::ServerIdentityChallenge>>>,
    host: String,
    port: u16,
}

pub fn certificate_fingerprint(cert: &[u8]) -> String {
    use sha2::{Digest, Sha256};
    Sha256::digest(cert)
        .iter()
        .map(|b| format!("{b:02X}"))
        .collect::<Vec<_>>()
        .join(":")
}

impl ServerCertVerifier for ServerIdentityVerifier {
    fn verify_server_cert(
        &self,
        cert: &CertificateDer<'_>,
        intermediates: &[CertificateDer<'_>],
        name: &ServerName<'_>,
        ocsp: &[u8],
        now: UnixTime,
    ) -> Result<ServerCertVerified, RustlsError> {
        let fingerprint = certificate_fingerprint(cert.as_ref());
        let result = if let Some(pin) = &self.pin {
            if pin == &fingerprint {
                Ok(ServerCertVerified::assertion())
            } else {
                Err(RustlsError::General(
                    "The server certificate has changed".into(),
                ))
            }
        } else {
            self.platform
                .verify_server_cert(cert, intermediates, name, ocsp, now)
        };
        if let Err(error) = &result {
            *self.failure.lock().unwrap() = Some(crate::ServerIdentityChallenge {
                host: self.host.clone(),
                port: self.port,
                fingerprint,
                previous_fingerprint: self.pin.clone(),
                reason: error.to_string(),
            });
        }
        result
    }

    fn verify_tls12_signature(
        &self,
        message: &[u8],
        cert: &CertificateDer<'_>,
        dss: &DigitallySignedStruct,
    ) -> Result<HandshakeSignatureValid, RustlsError> {
        self.platform.verify_tls12_signature(message, cert, dss)
    }
    fn verify_tls13_signature(
        &self,
        message: &[u8],
        cert: &CertificateDer<'_>,
        dss: &DigitallySignedStruct,
    ) -> Result<HandshakeSignatureValid, RustlsError> {
        self.platform.verify_tls13_signature(message, cert, dss)
    }
    fn supported_verify_schemes(&self) -> Vec<SignatureScheme> {
        self.platform.supported_verify_schemes()
    }
}

pub fn create_tls_connector(
    client_cert_pem: Option<&str>,
    client_key_pem: Option<&str>,
    host: &str,
    port: u16,
    pin: Option<String>,
    failure: Arc<std::sync::Mutex<Option<crate::ServerIdentityChallenge>>>,
) -> std::io::Result<TlsConnector> {
    let _ = rustls::crypto::aws_lc_rs::default_provider().install_default();

    let builder = rustls::ClientConfig::builder_with_provider(Arc::new(
        rustls::crypto::aws_lc_rs::default_provider(),
    ))
    .with_safe_default_protocol_versions()
    .map_err(|e| {
        std::io::Error::new(
            std::io::ErrorKind::Other,
            format!("TLS protocol version error: {:?}", e),
        )
    })?
    .dangerous()
    .with_custom_certificate_verifier(Arc::new(ServerIdentityVerifier {
        platform: rustls_platform_verifier::Verifier::new(Arc::new(
            rustls::crypto::aws_lc_rs::default_provider(),
        ))
        .map_err(std::io::Error::other)?,
        pin,
        failure,
        host: host.into(),
        port,
    }));

    let config = if let (Some(cert_pem), Some(key_pem)) = (client_cert_pem, client_key_pem) {
        if !cert_pem.trim().is_empty() && !key_pem.trim().is_empty() {
            let cert_chain: Vec<CertificateDer<'static>> =
                CertificateDer::pem_slice_iter(cert_pem.as_bytes())
                    .collect::<Result<Vec<_>, _>>()
                    .map_err(|e| {
                        std::io::Error::new(
                            std::io::ErrorKind::InvalidData,
                            format!("Invalid client cert PEM: {:?}", e),
                        )
                    })?;
            let key_der: PrivateKeyDer<'static> = PrivateKeyDer::from_pem_slice(key_pem.as_bytes())
                .map_err(|e| {
                    std::io::Error::new(
                        std::io::ErrorKind::InvalidData,
                        format!("Invalid client key PEM: {:?}", e),
                    )
                })?;
            builder
                .with_client_auth_cert(cert_chain, key_der)
                .map_err(|e| {
                    std::io::Error::new(
                        std::io::ErrorKind::Other,
                        format!("Failed to configure client certificate auth: {:?}", e),
                    )
                })?
        } else {
            builder.with_no_client_auth()
        }
    } else {
        builder.with_no_client_auth()
    };

    Ok(TlsConnector::from(Arc::new(config)))
}

pub async fn connect_tls(
    host: &str,
    port: u16,
    client_cert_pem: Option<&str>,
    client_key_pem: Option<&str>,
    identity_host: &str,
    identity_port: u16,
    pin: Option<String>,
    failure: Arc<std::sync::Mutex<Option<crate::ServerIdentityChallenge>>>,
) -> std::io::Result<TlsStream<TcpStream>> {
    let connector = create_tls_connector(
        client_cert_pem,
        client_key_pem,
        identity_host,
        identity_port,
        pin,
        failure,
    )?;
    let addr = (host, port);
    let tcp_stream = TcpStream::connect(addr).await?;
    let server_name =
        ServerName::try_from(identity_host.to_string()).map_err(std::io::Error::other)?;
    connector.connect(server_name, tcp_stream).await
}

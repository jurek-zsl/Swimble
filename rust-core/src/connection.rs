use std::sync::Arc;
use rustls::client::danger::{HandshakeSignatureValid, ServerCertVerified, ServerCertVerifier};
use rustls::pki_types::pem::PemObject;
use rustls::pki_types::{CertificateDer, PrivateKeyDer, ServerName, UnixTime};
use rustls::{DigitallySignedStruct, Error as RustlsError, SignatureScheme};
use tokio::net::TcpStream;
use tokio_rustls::client::TlsStream;
use tokio_rustls::TlsConnector;

#[derive(Debug)]
pub struct NoCertificateVerification;

impl ServerCertVerifier for NoCertificateVerification {
    fn verify_server_cert(
        &self,
        _end_entity: &CertificateDer<'_>,
        _intermediates: &[CertificateDer<'_>],
        _server_name: &ServerName<'_>,
        _ocsp_response: &[u8],
        _now: UnixTime,
    ) -> Result<ServerCertVerified, RustlsError> {
        Ok(ServerCertVerified::assertion())
    }

    fn verify_tls12_signature(
        &self,
        _message: &[u8],
        _cert: &CertificateDer<'_>,
        _dss: &DigitallySignedStruct,
    ) -> Result<HandshakeSignatureValid, RustlsError> {
        Ok(HandshakeSignatureValid::assertion())
    }

    fn verify_tls13_signature(
        &self,
        _message: &[u8],
        _cert: &CertificateDer<'_>,
        _dss: &DigitallySignedStruct,
    ) -> Result<HandshakeSignatureValid, RustlsError> {
        Ok(HandshakeSignatureValid::assertion())
    }

    fn supported_verify_schemes(&self) -> Vec<SignatureScheme> {
        rustls::crypto::aws_lc_rs::default_provider()
            .signature_verification_algorithms
            .supported_schemes()
    }
}

pub fn create_tls_connector(
    client_cert_pem: Option<&str>,
    client_key_pem: Option<&str>,
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
    .with_custom_certificate_verifier(Arc::new(NoCertificateVerification));

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
) -> std::io::Result<TlsStream<TcpStream>> {
    let connector = create_tls_connector(client_cert_pem, client_key_pem)?;
    let addr = format!("{}:{}", host, port);
    let tcp_stream = TcpStream::connect(&addr).await?;
    let server_name = ServerName::try_from(host.to_string())
        .unwrap_or_else(|_| ServerName::try_from("localhost".to_string()).unwrap());
    connector.connect(server_name, tcp_stream).await
}

use hickory_resolver::TokioResolver;
use std::net::IpAddr;
use std::sync::OnceLock;

#[derive(uniffi::Record, Debug, Clone, PartialEq, Eq)]
pub struct ResolvedEndpoint {
    pub host: String,
    pub port: u16,
    pub is_srv: bool,
}

fn get_resolver() -> &'static TokioResolver {
    static RESOLVER: OnceLock<TokioResolver> = OnceLock::new();
    RESOLVER.get_or_init(|| {
        TokioResolver::builder_tokio()
            .and_then(|b| b.build())
            .unwrap_or_else(|e| {
                eprintln!(
                    "[Swimble DNS] Failed to load system DNS config: {}, using default",
                    e
                );
                TokioResolver::builder_with_config(
                    hickory_resolver::config::ResolverConfig::default(),
                    hickory_resolver::net::runtime::TokioRuntimeProvider::default(),
                )
                .build()
                .expect("Failed to build default DNS resolver")
            })
    })
}

/// Resolves a Mumble server host and port.
/// If port is 64738 (the standard Mumble port) or 0, and host is not an IP address,
/// it queries the DNS SRV record `_mumble._tcp.<host>`.
/// Returns an ordered list of endpoints according to RFC 2782 (priority & weight),
/// falling back to the original host and port if no SRV records are found.
pub async fn resolve_mumble_endpoints(host: &str, port: u16) -> Vec<ResolvedEndpoint> {
    let clean_host = host.trim().trim_end_matches('.');
    if clean_host.is_empty() {
        return vec![ResolvedEndpoint {
            host: String::new(),
            port,
            is_srv: false,
        }];
    }

    // Skip SRV lookup if the target is already an IP address
    if clean_host.parse::<IpAddr>().is_ok() {
        return vec![ResolvedEndpoint {
            host: clean_host.to_string(),
            port,
            is_srv: false,
        }];
    }

    // In original Mumble, SRV lookup is performed when using the default port (64738 or 0)
    if port != 64738 && port != 0 {
        return vec![ResolvedEndpoint {
            host: clean_host.to_string(),
            port,
            is_srv: false,
        }];
    }

    let default_effective_port = if port == 0 { 64738 } else { port };

    // Form SRV query domain: `_mumble._tcp.<domain>`
    let srv_domain = if clean_host.starts_with("_mumble._tcp.") {
        clean_host.to_string()
    } else {
        format!("_mumble._tcp.{}", clean_host)
    };

    let resolver = get_resolver();
    match resolver.srv_lookup(&srv_domain).await {
        Ok(lookup) => {
            let mut srv_entries: Vec<SrvEntry> = Vec::new();
            for record in lookup.answers() {
                if let hickory_resolver::proto::rr::RData::SRV(srv) = &record.data {
                    let target_raw = srv.target.to_utf8();
                    let target = target_raw.trim().trim_end_matches('.').to_string();
                    if target.is_empty() || target == "." {
                        continue;
                    }
                    srv_entries.push(SrvEntry {
                        priority: srv.priority,
                        weight: srv.weight,
                        port: srv.port,
                        target,
                    });
                }
            }

            if !srv_entries.is_empty() {
                let sorted = sort_srv_records(srv_entries);
                return sorted
                    .into_iter()
                    .map(|e| ResolvedEndpoint {
                        host: e.target,
                        port: e.port,
                        is_srv: true,
                    })
                    .collect();
            }
        }
        Err(_) => {
            // No SRV record found or query failed; fall through to direct fallback
        }
    }

    vec![ResolvedEndpoint {
        host: clean_host.to_string(),
        port: default_effective_port,
        is_srv: false,
    }]
}

#[derive(Debug, Clone)]
struct SrvEntry {
    priority: u16,
    weight: u16,
    port: u16,
    target: String,
}

/// Sorts SRV records according to RFC 2782:
/// - Ascending priority (lowest priority number comes first).
/// - For entries with identical priority, order by weight (higher weights prioritized).
fn sort_srv_records(mut entries: Vec<SrvEntry>) -> Vec<SrvEntry> {
    entries.sort_by_key(|e| e.priority);

    let mut result = Vec::with_capacity(entries.len());
    let mut i = 0;
    while i < entries.len() {
        let current_prio = entries[i].priority;
        let mut group = Vec::new();
        while i < entries.len() && entries[i].priority == current_prio {
            group.push(entries[i].clone());
            i += 1;
        }

        // RFC 2782 selects by weight without replacement; a deterministic
        // descending sort would send every client to the same endpoint.
        while !group.is_empty() {
            let sum: u32 = group.iter().map(|entry| entry.weight as u32).sum();
            let selected = if sum == 0 {
                rand::random_range(0..group.len())
            } else {
                let draw = rand::random_range(1..=sum);
                let mut cumulative = 0;
                group
                    .iter()
                    .position(|entry| {
                        cumulative += entry.weight as u32;
                        cumulative >= draw
                    })
                    .unwrap_or(0)
            };
            result.push(group.remove(selected));
        }
    }

    result
}

/// Resolves the single primary endpoint for a Mumble host via DNS SRV (`_mumble._tcp.<host>`).
#[uniffi::export]
pub async fn resolve_mumble_srv(host: String, port: u16) -> ResolvedEndpoint {
    let rt = crate::ping::get_tokio_runtime();
    let host_clone = host.clone();
    let handle = rt.spawn(async move {
        let endpoints = resolve_mumble_endpoints(&host_clone, port).await;
        endpoints.into_iter().next().unwrap_or(ResolvedEndpoint {
            host: host_clone,
            port,
            is_srv: false,
        })
    });
    match handle.await {
        Ok(res) => res,
        Err(_) => ResolvedEndpoint {
            host,
            port,
            is_srv: false,
        },
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_sort_srv_records_rfc2782() {
        let entries = vec![
            SrvEntry {
                priority: 20,
                weight: 10,
                port: 64740,
                target: "backup.example.com".into(),
            },
            SrvEntry {
                priority: 10,
                weight: 5,
                port: 64738,
                target: "primary-low.example.com".into(),
            },
            SrvEntry {
                priority: 10,
                weight: 20,
                port: 64739,
                target: "primary-high.example.com".into(),
            },
        ];

        let sorted = sort_srv_records(entries);
        assert_eq!(sorted.len(), 3);
        assert_eq!(sorted[0].priority, 10);
        assert_eq!(sorted[1].priority, 10);
        assert_ne!(sorted[0].target, sorted[1].target);
        assert_eq!(sorted[2].target, "backup.example.com");
    }

    #[tokio::test]
    async fn test_resolve_ip_skips_srv() {
        let res = resolve_mumble_endpoints("127.0.0.1", 64738).await;
        assert_eq!(res.len(), 1);
        assert_eq!(res[0].host, "127.0.0.1");
        assert_eq!(res[0].port, 64738);
        assert!(!res[0].is_srv);
    }

    #[tokio::test]
    async fn test_resolve_custom_port_skips_srv() {
        let res = resolve_mumble_endpoints("example.com", 12345).await;
        assert_eq!(res.len(), 1);
        assert_eq!(res[0].host, "example.com");
        assert_eq!(res[0].port, 12345);
        assert!(!res[0].is_srv);
    }

    #[tokio::test]
    async fn test_resolve_fallback_when_no_srv() {
        let res = resolve_mumble_endpoints("mumble.info", 64738).await;
        assert_eq!(res.len(), 1);
        assert_eq!(res[0].host, "mumble.info");
        assert_eq!(res[0].port, 64738);
        assert!(!res[0].is_srv);
    }
}

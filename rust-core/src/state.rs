use std::collections::HashMap;
use crate::{
    BanEntryInfo, ChannelInfo, ConnectionStatus, RegisteredUser, ServerConnectionInfo,
    TalkingState, UserInfo,
};
use crate::proto;

#[derive(Clone, Debug)]
pub struct ClientState {
    pub my_session: Option<u32>,
    pub channels: HashMap<u32, ChannelInfo>,
    pub users: HashMap<u32, UserInfo>,
    pub connection_status: ConnectionStatus,
    pub user_volumes: HashMap<u32, f32>,
    pub server_info: ServerConnectionInfo,
    pub registered_users: Vec<RegisteredUser>,
    pub ban_list: Vec<BanEntryInfo>,
}

impl Default for ClientState {
    fn default() -> Self {
        Self::new()
    }
}

impl ClientState {
    pub fn new() -> Self {
        Self {
            my_session: None,
            channels: HashMap::new(),
            users: HashMap::new(),
            connection_status: ConnectionStatus::Disconnected,
            user_volumes: HashMap::new(),
            server_info: ServerConnectionInfo {
                server_version: "Unknown".into(),
                server_os: "Unknown".into(),
                server_os_version: "".into(),
                welcome_text: "".into(),
                tls_cipher: "Unknown".into(),
                max_bandwidth_kbps: 64,
                max_users: 100,
                using_udp_tunnel: false,
                tcp_ping_ms: 0.0,
                udp_ping_ms: 0.0,
                good_packets: 0,
                late_packets: 0,
                lost_packets: 0,
                resync_packets: 0,
                udp_packets_sent: 0,
                tcp_packets_sent: 0,
            },
            registered_users: Vec::new(),
            ban_list: Vec::new(),
        }
    }

    pub fn reset(&mut self) {
        self.my_session = None;
        self.channels.clear();
        self.users.clear();
        self.registered_users.clear();
        self.ban_list.clear();
        self.connection_status = ConnectionStatus::Disconnected;
        self.server_info = Self::new().server_info;
    }

    pub fn update_channel(&mut self, state: proto::ChannelState) -> Option<ChannelInfo> {
        let id = state.channel_id?;
        let entry = self.channels.entry(id).or_insert_with(|| ChannelInfo {
            id,
            parent_id: None,
            name: String::new(),
            description: String::new(),
            position: 0,
            is_temporary: false,
            is_enter_restricted: false,
            can_enter: true,
        });

        if let Some(parent) = state.parent {
            entry.parent_id = Some(parent);
        }
        if let Some(name) = state.name {
            entry.name = name;
        }
        if let Some(desc) = state.description {
            entry.description = desc;
        }
        if let Some(pos) = state.position {
            entry.position = pos;
        }
        if let Some(temp) = state.temporary {
            entry.is_temporary = temp;
        }
        if let Some(restricted) = state.is_enter_restricted {
            entry.is_enter_restricted = restricted;
        }
        if let Some(can) = state.can_enter {
            entry.can_enter = can;
            if !can {
                entry.is_enter_restricted = true;
            }
        }

        Some(entry.clone())
    }

    pub fn remove_channel(&mut self, channel_id: u32) -> Option<ChannelInfo> {
        self.channels.remove(&channel_id)
    }

    pub fn update_user(&mut self, state: proto::UserState) -> UserInfo {
        let session = state.session.unwrap_or(0);
        let entry = self.users.entry(session).or_insert_with(|| UserInfo {
            session_id: session,
            channel_id: 0,
            name: String::new(),
            is_muted: false,
            is_deafened: false,
            is_self_muted: false,
            is_self_deafened: false,
            is_priority_speaker: false,
            is_recording: false,
            comment: None,
            user_id: None,
            is_talking: false,
            talking_state: TalkingState::Passive,
            cert_hash: None,
        });

        if let Some(cid) = state.channel_id {
            entry.channel_id = cid;
        }
        if let Some(name) = state.name {
            entry.name = name;
        }
        if let Some(mute) = state.mute {
            entry.is_muted = mute;
        }
        if let Some(deaf) = state.deaf {
            entry.is_deafened = deaf;
        }
        if let Some(smute) = state.self_mute {
            entry.is_self_muted = smute;
        }
        if let Some(sdeaf) = state.self_deaf {
            entry.is_self_deafened = sdeaf;
        }
        if let Some(priority) = state.priority_speaker {
            entry.is_priority_speaker = priority;
        }
        if let Some(rec) = state.recording {
            entry.is_recording = rec;
        }
        if let Some(comment) = state.comment {
            entry.comment = Some(comment);
        }
        if let Some(uid) = state.user_id {
            entry.user_id = Some(uid);
        }
        if let Some(hash) = state.hash {
            entry.cert_hash = Some(hash);
        }

        entry.clone()
    }

    pub fn remove_user(&mut self, session: u32) -> Option<UserInfo> {
        self.users.remove(&session)
    }

    pub fn set_user_talking(
        &mut self,
        session_id: u32,
        is_talking: bool,
        talking_state: TalkingState,
    ) -> Option<UserInfo> {
        if let Some(user) = self.users.get_mut(&session_id) {
            user.is_talking = is_talking;
            user.talking_state = talking_state;
            Some(user.clone())
        } else {
            None
        }
    }

    pub fn channels_list(&self) -> Vec<ChannelInfo> {
        let mut list: Vec<ChannelInfo> = self.channels.values().cloned().collect();
        list.sort_by(|a, b| a.position.cmp(&b.position).then_with(|| a.id.cmp(&b.id)));
        list
    }

    pub fn users_list(&self) -> Vec<UserInfo> {
        let mut list: Vec<UserInfo> = self.users.values().cloned().collect();
        list.sort_by(|a, b| a.name.cmp(&b.name));
        list
    }
}

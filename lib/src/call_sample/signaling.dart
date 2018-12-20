import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:flutter_webrtc/webrtc.dart';
import 'random_string.dart';

enum SignalingState {
  CallStateNew,
  CallStateRinging,
  CallStateInvite,
  CallStateConnected,
  CallStateBye,
  ConnectionOpen,
  ConnectionClosed,
  ConnectionError,
}

/*
 * callbacks for Signaling API.
 */
typedef void SignalingStateCallback(SignalingState state);
typedef void StreamStateCallback(MediaStream stream);
typedef void OtherEventCallback(dynamic event);
typedef void DataChannelMessageCallback(RTCDataChannel dc, data);

class Signaling {
  String _selfId = randomNumeric(6);
  var _socket;
  var _sessionId;
  var _url;
  var _name;
  var _peerConnections = new Map<String, RTCPeerConnection>();
  var _daChannels = new Map<int, RTCDataChannel>();
  MediaStream _localStream;
  List<MediaStream> _remoteStreams;
  SignalingStateCallback onStateChange;
  StreamStateCallback onLocalStream;
  StreamStateCallback onAddRemoteStream;
  StreamStateCallback onRemoveRemoteStream;
  OtherEventCallback onPeersUpdate;
  DataChannelMessageCallback onDataChannel;

  Map<String, dynamic> _iceServers = {
    'iceServers': [
      {'url': 'stun:stun.l.google.com:19302'},
      /**
       * turn server configuration example.
      {
        'url': 'turn:123.45.67.89:3478',
        'username': 'change_to_real_user',
        'credential': 'change_to_real_secret'
      },
       */
    ]
  };

  final Map<String, dynamic> _config = {
    'mandatory': {},
    'optional': [
      {'DtlsSrtpKeyAgreement': true},
    ],
  };

  final Map<String, dynamic> _constraints = {
    'mandatory': {
      'OfferToReceiveAudio': true,
      'OfferToReceiveVideo': true,
    },
    'optional': [],
  };

  Signaling(this._url, this._name);

  close() {

    if (_localStream != null) {
      _localStream.dispose();
      _localStream = null;
    }

    _peerConnections.forEach((key, pc){
      pc.close();
    });
    if (_socket != null)
      _socket.close();
  }

  void invite(String peer_id, String media) {
    this._sessionId = this._selfId + '-' + peer_id;

    if (this.onStateChange != null) {
      this.onStateChange(SignalingState.CallStateNew);
    }

    _createPeerConnection(peer_id, media).then((pc) {
      _peerConnections[peer_id] = pc;
      _createOffer(peer_id, pc, media);
    });
  }

  void bye() {
    _send('bye', {
      'session_id': this._sessionId,
      'from': this._selfId,
    });
  }

  void onMessage(message) async {
    Map<String, dynamic> mapData = message;
    var data = mapData['data'];

    switch(mapData['type']){

      case 'peers':
        {
          List<dynamic> peers = data;
          if(this.onPeersUpdate != null) {
            Map<String, dynamic> event = new  Map<String, dynamic>();
            event['self'] = _selfId;
            event['peers'] = peers;
            this.onPeersUpdate(event);
          }
        }
        break;
      case 'offer':
        {
          var id = data['from'];
          var description = data['description'];
          var media = data['media'];
          var sessionId = data['session_id'];
          this._sessionId = sessionId;

          if (this.onStateChange != null) {
            this.onStateChange(SignalingState.CallStateNew);
          }

          _createPeerConnection(id, media).then((pc) {
            _peerConnections[id] = pc;
            pc.setRemoteDescription(
                new RTCSessionDescription(description['sdp'], description['type']));
            _createAnswer(id, pc);
          });
        }
        break;
      case 'answer':
        {
          var id = data['from'];
          var description = data['description'];

          var pc = _peerConnections[id];
          if (pc != null) {
            pc.setRemoteDescription(
                new RTCSessionDescription(description['sdp'], description['type']));
          }
        }
        break;
      case 'candidate':
        {
          var id = data['from'];
          var candidateMap = data['candidate'];
          var pc = _peerConnections[id];

          if (pc != null) {
            RTCIceCandidate candidate = new RTCIceCandidate(
                candidateMap['candidate'],
                candidateMap['sdpMid'],
                candidateMap['sdpMLineIndex']);
            pc.addCandidate(candidate);
          }
        }
        break;
      case 'leave':
        {
          var id = data;
          _peerConnections.remove(id);
          _daChannels.remove(id);

          if (_localStream != null) {
            _localStream.dispose();
            _localStream = null;
          }

          var pc = _peerConnections[id];
          if (pc != null) {
            pc.close();
            _peerConnections.remove(id);
          }
          this._sessionId = null;
          if (this.onStateChange != null) {
            this.onStateChange(SignalingState.CallStateBye);
          }
        }
        break;
      case 'bye':
        {
          var from = data['from'];
          var to = data['to'];
          var sessionId = data['session_id'];
          print('bye: ' + sessionId);

          if (_localStream != null) {
            _localStream.dispose();
            _localStream = null;
          }

          var pc = _peerConnections[to];
          if (pc != null) {
            pc.close();
            _peerConnections.remove(to);
          }
          this._sessionId = null;
          if (this.onStateChange != null) {
            this.onStateChange(SignalingState.CallStateBye);
          }
        }
        break;
      case 'keepalive':
        {
          print('keepalive response!');
        }
        break;
      default:
        break;
    }
  }

  void connect() async {
    try {
      _socket = await WebSocket.connect(_url);

      if (this.onStateChange != null) {
        this.onStateChange(SignalingState.ConnectionOpen);
      }

      _socket.listen((data) {
        print('Recivied data: ' + data);
        JsonDecoder decoder = new JsonDecoder();
        this.onMessage(decoder.convert(data));
      }, onDone: () {
        print('Closed by server!');
        if (this.onStateChange != null) {
          this.onStateChange(SignalingState.ConnectionClosed);
        }
      });

      _send('new', {
        'name': _name,
        'id': _selfId,
        'user_agent': 'flutter-webrtc/'+ Platform.operatingSystem +'-plugin 0.0.1'
      });
    }catch(e){
      if(this.onStateChange != null){
        this.onStateChange(SignalingState.ConnectionError);
      }
    }
  }

  Future<MediaStream> createStream() async {
    final Map<String, dynamic> mediaConstraints = {
      'audio': true,
      'video': {
        'mandatory': {
          'minWidth': '640', // Provide your own width, height and frame rate here
          'minHeight': '480',
          'minFrameRate': '30',
        },
        'facingMode': 'user',
        'optional': [],
      }
    };

    MediaStream stream = await navigator.getUserMedia(mediaConstraints);
    if(this.onLocalStream != null){
      this.onLocalStream(stream);
    }
    return stream;
  }

  _createPeerConnection(id, media) async {
    _localStream = await createStream();
    RTCPeerConnection pc = await createPeerConnection(_iceServers, _config);
    pc.addStream(_localStream);
    pc.onIceCandidate = (candidate) {
      _send('candidate', {
        'to': id,
        'candidate': {
          'sdpMLineIndex': candidate.sdpMlineIndex,
          'sdpMid': candidate.sdpMid,
          'candidate': candidate.candidate,
        },
        'session_id': this._sessionId,
      });
    };

    pc.onAddStream = (stream) {
      if(this.onAddRemoteStream != null)
        this.onAddRemoteStream(stream);
      //_remoteStreams.add(stream);
    };

    pc.onRemoveStream = (stream) {
      if(this.onRemoveRemoteStream != null)
        this.onRemoveRemoteStream(stream);
      _remoteStreams.removeWhere((it) {
        return (it.id == stream.id);
      });
    };

    pc.onDataChannel = (channel) {
      _addDataChannel(id, channel);
    };

    return pc;
  }

  _addDataChannel(id, RTCDataChannel channel) {
    channel.onDataChannelState = (e) {};
    channel.onMessage = (data) {
      if(this.onDataChannel != null)
        this.onDataChannel(channel, data);
    };
    _daChannels[id] = channel;
  }

  _createDataChannel(id, RTCPeerConnection pc, {label: 'fileTransfer'}) async {
    RTCDataChannelInit dataChannelDict = new RTCDataChannelInit();
    RTCDataChannel channel = await pc.createDataChannel(label, dataChannelDict);
    _addDataChannel(id, channel);
  }

  _createOffer(String id, RTCPeerConnection pc, String media) async {
    try {
      RTCSessionDescription s = await pc.createOffer(_constraints);
      pc.setLocalDescription(s);
      _send('offer', {
        'to': id,
        'description': {'sdp': s.sdp, 'type': s.type},
        'session_id': this._sessionId,
        'media': media,
      });
    } catch (e) {
      print(e.toString());
    }
  }

  _createAnswer(String id, RTCPeerConnection pc) async {
    try {
      RTCSessionDescription s = await pc.createAnswer(_constraints);
      pc.setLocalDescription(s);
      _send('answer', {
        'to': id,
        'description': {'sdp': s.sdp, 'type': s.type},
        'session_id': this._sessionId,
      });
    } catch (e) {
      print(e.toString());
    }
  }

  _send(event, data) {
    data['type'] = event;
    JsonEncoder encoder = new JsonEncoder();
    if (_socket != null) _socket.add(encoder.convert(data));
    print('send: ' + encoder.convert(data));
  }
}

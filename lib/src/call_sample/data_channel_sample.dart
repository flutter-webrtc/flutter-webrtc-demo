import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:core';
import 'dart:async';
import 'signaling.dart';

class DataChannelSample extends StatefulWidget {
  static String tag = 'call_sample';

  final String ip;

  DataChannelSample({Key key, @required this.ip}) : super(key: key);

  @override
  _DataChannelSampleState createState() => new _DataChannelSampleState(serverIP: ip);
}

class _DataChannelSampleState extends State<DataChannelSample> {
  Signaling _signaling;
  String _displayName =
      Platform.localHostname + '(' + Platform.operatingSystem + ")";
  List<dynamic> _peers;
  var _selfId;
  bool _inCalling = false;
  final String serverIP;
  var _dataChannel;
  Timer _timer;
  var _text = '';
  _DataChannelSampleState({Key key, @required this.serverIP});

  @override
  initState() {
    super.initState();
    _connect();
  }

  @override
  deactivate() {
    super.deactivate();
    if (_signaling != null) _signaling.close();
    if(_timer != null){
      _timer.cancel();
    }
  }

  void _connect() async {
    if (_signaling == null) {
      _signaling = new Signaling('ws://' + serverIP + ':4442', _displayName)
        ..connect();

      _signaling.onDataChannelMessage = (dc, text){
        setState(() {
          _text = text;
        });
      };

      _signaling.onDtaChannel = (channel){
        _dataChannel = channel;
      };

      _signaling.onStateChange = (SignalingState state) {
        switch (state) {
          case SignalingState.CallStateNew:
            {
              this.setState(() {
                _inCalling = true;
              });
              _timer = new Timer.periodic(Duration(seconds: 1), _handleDataChannelTest);
              break;
            }
          case SignalingState.CallStateBye:
            {
              this.setState(() {
                _inCalling = false;
              });
              if(_timer != null){
                _timer.cancel();
                _timer = null;
              }
              _dataChannel = null;
              _text = '';
              break;
            }
          case SignalingState.CallStateInvite:
          case SignalingState.CallStateConnected:
          case SignalingState.CallStateRinging:
          case SignalingState.ConnectionClosed:
          case SignalingState.ConnectionError:
          case SignalingState.ConnectionOpen:
            break;
        }
      };

      _signaling.onPeersUpdate = ((event) {
        this.setState(() {
          _selfId = event['self'];
          _peers = event['peers'];
        });
      });
    }
  }

  _handleDataChannelTest(Timer timer) async {
    if(_dataChannel != null){
      _dataChannel.send('text', 'Say hello ' + timer.tick.toString() + ' times, from [' + _selfId + ']');
    }
  }

  _invitePeer(context, peerId) async {
    if (_signaling != null && peerId != _selfId) {
      _signaling.invite(peerId, 'data');
    }
  }

  _hangUp() {
    if (_signaling != null) {
      _signaling.bye();
    }
  }

  _buildRow(context, peer) {
    var self = (peer['id'] == _selfId);
    return ListBody(children: <Widget>[
      ListTile(
        title: Text(self
            ? peer['name'] + '[Your self]'
            : peer['name'] + '[' + peer['user_agent'] + ']'),
        onTap: () => _invitePeer(context, peer['id']),
        trailing: Icon(Icons.videocam),
        subtitle: Text('id: ' + peer['id']),
      ),
      Divider()
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return new Scaffold(
      appBar: new AppBar(
        title: new Text('Data Channel Sample'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: null,
            tooltip: 'setup',
          ),
        ],
      ),
      floatingActionButton: _inCalling
          ? FloatingActionButton(
              onPressed: _hangUp,
              tooltip: 'Hangup',
              child: new Icon(Icons.call_end),
            )
          : null,
      body: _inCalling? new Center(
              child: new Container(
              child:  Text('Recevied => ' + _text),
              ),
              ) : new ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.all(0.0),
              itemCount: (_peers != null ? _peers.length : 0),
              itemBuilder: (context, i) {
                return _buildRow(context, _peers[i]);
              }),
    );
  }
}

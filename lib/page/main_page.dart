import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:planner/page/login_page.dart';

class MainPage extends StatefulWidget {
  const MainPage({Key? key}) : super(key: key);

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  final TextEditingController _referenceController = TextEditingController();
  final TextEditingController _meetingDataController = TextEditingController();
  String _reference = '';
  String _meetingData = '';
  int _elapsedSeconds = 0;
  Timer? _timer;
  bool _isPlaying = false;
  User? _user;
  StreamSubscription<User?>? _authStateSubscription;

  @override
  void initState() {
    super.initState();
    _initializeFirebase();
    _checkUser();
  }

  Future<void> _initializeFirebase() async {
    await Firebase.initializeApp();
  }

  Future<void> _checkUser() async {
    _authStateSubscription = FirebaseAuth.instance.authStateChanges().listen((User? user) {
      if (mounted) {
        setState(() {
          _user = user;
        });
        if (user == null) {
          Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => AuthPage(),));
        }
      }
    });
  }

  void _startTimer() {
    setState(() {
      _isPlaying = true;
      _elapsedSeconds = 0;
    });
    _timer = Timer.periodic(Duration(seconds: 1), (timer) {
      setState(() {
        _elapsedSeconds++;
      });
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    setState(() {
      _isPlaying = false;
      _referenceController.clear();
      _meetingDataController.clear();
    });
    _saveDataToFirestore();
    _elapsedSeconds = 0;
  }

  Future<void> _saveDataToFirestore() async {
    if (_user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('로그인이 필요합니다.')),
      );
      return;
    }

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(_user!.uid)
          .collection('records')
          .add({
        'reference': _reference,
        'meetingData': _meetingData,
        'time': _elapsedSeconds,
        'timestamp': FieldValue.serverTimestamp(),
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('데이터가 저장되었습니다.')),
      );
      _reference = "";
      _meetingData = "";
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('데이터 저장에 실패했습니다: $e')),
      );
    }
  }

  Future<void> _updateRecord(
      String docId, String reference, String meetingData) async {
    if (_user == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(_user!.uid)
          .collection('records')
          .doc(docId)
          .update({
        'reference': reference,
        'meetingData': meetingData,
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('데이터가 수정되었습니다.')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('데이터 수정에 실패했습니다: $e')),
      );
    }
  }

  Future<void> _deleteRecord(String docId) async {
    if (_user == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(_user!.uid)
          .collection('records')
          .doc(docId)
          .delete();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('데이터가 삭제되었습니다.')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('데이터 삭제에 실패했습니다: $e')),
      );
    }
  }

  void _showEditDialog(BuildContext context, String docId, String reference,
      String meetingData) {
    TextEditingController _referenceController =
        TextEditingController(text: reference);
    TextEditingController _meetingDataController =
        TextEditingController(text: meetingData);

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('데이터 수정/삭제'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                  controller: _referenceController,
                  decoration: InputDecoration(labelText: '제목')),
              TextField(
                  controller: _meetingDataController,
                  decoration: InputDecoration(labelText: '부제목')),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('취소'),
            ),
            TextButton(
              onPressed: () {
                _updateRecord(docId, _referenceController.text,
                    _meetingDataController.text);
                Navigator.pop(context);
              },
              child: Text('수정'),
            ),
            TextButton(
              onPressed: () {
                _deleteRecord(docId);
                Navigator.pop(context);
              },
              child: Text('삭제'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    }

  @override
  void dispose() {
    _authStateSubscription?.cancel(); // 스트림 구독 취소
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Main Page'),
        actions: [
          IconButton(
            icon: Icon(Icons.menu),
            onPressed: () {
              showModalBottomSheet(
                context: context,
                builder: (BuildContext context) {
                  return SafeArea(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        ListTile(
                          leading: Icon(Icons.logout),
                          title: Text('로그아웃'),
                          onTap: () {
                            Navigator.pop(context); // Bottom sheet 닫기
                          },
                        ),
                        ListTile(
                          leading: Icon(Icons.logout),
                          title: Text('그룹생성'),
                          onTap: () {
                            Navigator.pop(context); // Bottom sheet 닫기
                          },
                        ),
                        ListTile(
                          leading: Icon(Icons.logout),
                          title: Text('그룹참가'),
                          onTap: () {
                            Navigator.pop(context); // Bottom sheet 닫기
                          },
                        ),
                        ListTile(
                          leading: Icon(Icons.logout),
                          title: Text('그룹보기'),
                          onTap: () {
                            Navigator.pop(context); // Bottom sheet 닫기
                          },
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                Expanded(
                  child: Container(
                    color: Colors.white,
                    child: StreamBuilder<QuerySnapshot>(
                      stream: _user != null
                          ? FirebaseFirestore.instance
                              .collection('users')
                              .doc(_user!.uid)
                              .collection('records')
                              .snapshots()
                          : Stream.empty(),
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return Center(child: Text('데이터를 불러오는 중 오류가 발생했습니다.'));
                        }
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return Center(child: Text('데이터를 불러오는 중입니다.'));
                        }
                        if (snapshot.data == null ||
                            snapshot.data!.docs.isEmpty) {
                          return Center(child: Text('저장된 데이터가 없습니다.'));
                        }
                        return ListView(
                          children: snapshot.data!.docs
                              .map((DocumentSnapshot document) {
                            Map<String, dynamic> data =
                                document.data() as Map<String, dynamic>;
                            return InkWell(
                              onTap: () {
                                _showEditDialog(context, document.id,
                                    data['reference'], data['meetingData']);
                              },
                              child: ListTile(
                                title: Text(data['reference'] ?? ''),
                                subtitle: Text(data['meetingData'] ?? ''),
                                trailing: Text(
                                    '${data['time'] ~/ 60}:${(data['time'] % 60).toString().padLeft(2, '0')}'),
                              ),
                            );
                          }).toList(),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            bottom: 20,
            left: 20,
            right: 20,
            child: Container(
              height: 50,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.7),
                    blurRadius: 5.0,
                    spreadRadius: 1.0,
                    offset: Offset(5, 7),
                  )
                ],
              ),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _referenceController,
                        decoration: InputDecoration(
                            hintText: "제목", border: InputBorder.none),
                        onChanged: (value) => _reference = value,
                      ),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _meetingDataController,
                        decoration: InputDecoration(
                            hintText: "부제목", border: InputBorder.none),
                        onChanged: (value) => _meetingData = value,
                      ),
                    ),
                    VerticalDivider(),
                    Padding(padding: EdgeInsets.symmetric(horizontal: 4)),
                    Text(
                        '${_elapsedSeconds ~/ 60}:${(_elapsedSeconds % 60).toString().padLeft(2, '0')}'),
                    Padding(padding: EdgeInsets.symmetric(horizontal: 2)),
                    IconButton(
                      icon: Icon(_isPlaying ? Icons.stop : Icons.play_arrow,
                          color: Colors.purple),
                      onPressed: () {
                        if (_isPlaying) {
                          _stopTimer();
                        } else {
                          _startTimer();
                        }
                      },
                    ),
                    Padding(padding: EdgeInsets.symmetric(horizontal: 5)),
                    Column(
                      spacing: 2,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 5,
                          height: 5,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(width: 0.5, color: Colors.black),
                          ),
                        ),
                        Container(
                          width: 5,
                          height: 5,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(width: 0.5, color: Colors.black),
                          ),
                        ),
                        Container(
                          width: 5,
                          height: 5,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(width: 0.5, color: Colors.black),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

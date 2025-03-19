import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:planner/page/login_page.dart';
import 'package:planner/page/create_group_page.dart';
import 'package:planner/page/join_group_page.dart';
import 'package:planner/page/group_list_page.dart';

class MainPage extends StatefulWidget {
  const MainPage({Key? key}) : super(key: key);

  @override
  State<MainPage> createState() => _MainPageState();
}

enum SortOption {
  latest,    // 최신순
  oldest,    // 오래된순
  time,      // 기록 시간순
  date,      // 날짜별
}

class _MainPageState extends State<MainPage> with WidgetsBindingObserver {
  final TextEditingController _referenceController = TextEditingController();
  final TextEditingController _meetingDataController = TextEditingController();
  String _reference = '';
  String _meetingData = '';
  int _elapsedSeconds = 0;
  Timer? _timer;
  bool _isPlaying = false;
  bool _isPaused = false;
  User? _user;
  StreamSubscription<User?>? _authStateSubscription;
  SortOption _currentSortOption = SortOption.latest;
  final ValueNotifier<int> _elapsedSecondsNotifier = ValueNotifier<int>(0);

  // 키보드 포커스 노드 추가
  final FocusNode _keyboardFocusNode = FocusNode();
  final FocusNode _referenceFocusNode = FocusNode();
  final FocusNode _meetingDataFocusNode = FocusNode();
  
  // 전역 포커스 변경 감지 구독
  late final StreamSubscription<bool> _focusSubscription;
  
  // 텍스트 필드 포커스 상태 추적
  bool _isTextFieldFocused = false;

  @override
  void initState() {
    super.initState();
    _initializeFirebase();
    _checkUser();
    
    // 위젯 바인딩 옵저버 등록
    WidgetsBinding.instance.addObserver(this);
    
    // 포커스 노드 설정 및 감시
    _setupFocusNodes();
    
    // 전체 키보드 포커스 설정
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FocusScope.of(context).requestFocus(_keyboardFocusNode);
    });
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
      _isPaused = false;
    });
    _timer = Timer.periodic(Duration(seconds: 1), (timer) {
      _elapsedSecondsNotifier.value++;
    });
  }

  void _pauseTimer() {
    _timer?.cancel();
    setState(() {
      _isPaused = true;
      _isPlaying = false;
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    setState(() {
      _isPlaying = false;
      _isPaused = false;
      _referenceController.clear();
      _meetingDataController.clear();
      _reference = "";
      _meetingData = "";
    });
    _saveDataToFirestore();
    _elapsedSecondsNotifier.value = 0;
  }

  void _resetTimer() {
    _timer?.cancel();
    setState(() {
      _isPlaying = false;
      _isPaused = false;
      _referenceController.clear();
      _meetingDataController.clear();
      _reference = "";
      _meetingData = "";
    });
    _elapsedSecondsNotifier.value = 0;
  }

  Future<void> _saveDataToFirestore() async {
    if (_user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('로그인이 필요합니다.')),
      );
      return;
    }

    try {
      final now = DateTime.now();
      
      await FirebaseFirestore.instance
          .collection('users')
          .doc(_user!.uid)
          .collection('records')
          .add({
        'reference': _reference,
        'meetingData': _meetingData,
        'time': _elapsedSecondsNotifier.value,
        'timestamp': FieldValue.serverTimestamp(),
        'date': '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}',
        'timeOfDay': '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
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
      String meetingData, {String? date, String? timeOfDay}) {
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
              if (date != null && timeOfDay != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text('기록 시간: $date $timeOfDay', 
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
                ),
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

  void _logout() async {
    await FirebaseAuth.instance.signOut();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // 앱 상태 변경 시 포커스 확인
    if (state == AppLifecycleState.resumed) {
      _checkFocusState();
    }
  }

  void _setupFocusNodes() {
    // 직접 포커스 이벤트 감시
    _referenceFocusNode.addListener(_checkFocusState);
    _meetingDataFocusNode.addListener(_checkFocusState);
    
    // 글로벌 포커스 변경 감시 스트림 생성
    final focusController = StreamController<bool>.broadcast();
    _focusSubscription = focusController.stream.listen((hasFocus) {
      _checkFocusState();
    });
    
    // 모든 프레임 업데이트 후 포커스 상태 체크
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkFocusState();
      
      // 주기적으로 포커스 상태 체크
      Timer.periodic(Duration(milliseconds: 100), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        _checkFocusState();
      });
    });
  }
  
  void _checkFocusState() {
    if (!mounted) return;
    
    final hasFocus = _referenceFocusNode.hasFocus || _meetingDataFocusNode.hasFocus;
    if (hasFocus != _isTextFieldFocused) {
      setState(() {
        _isTextFieldFocused = hasFocus;
      });
    }
  }

  @override
  void dispose() {
    _authStateSubscription?.cancel();
    _timer?.cancel();
    _elapsedSecondsNotifier.dispose();
    _keyboardFocusNode.dispose();
    _referenceFocusNode.removeListener(_checkFocusState);
    _referenceFocusNode.dispose();
    _meetingDataFocusNode.removeListener(_checkFocusState);
    _meetingDataFocusNode.dispose();
    _focusSubscription.cancel();
    
    // 위젯 바인딩 옵저버 제거
    WidgetsBinding.instance.removeObserver(this);
    
    super.dispose();
  }

  // 정렬 옵션에 따라 쿼리를 반환하는 함수
  Query<Map<String, dynamic>> _getSortedQuery() {
    if (_user == null) {
      return FirebaseFirestore.instance.collection('dummy');
    }
    
    Query<Map<String, dynamic>> query = FirebaseFirestore.instance
        .collection('users')
        .doc(_user!.uid)
        .collection('records');

    // 기본적으로 timestamp로만 정렬하고 나머지는 클라이언트에서 처리
    switch (_currentSortOption) {
      case SortOption.latest:
        return query.orderBy('timestamp', descending: true);
      case SortOption.oldest:
        return query.orderBy('timestamp', descending: false);
      case SortOption.time:
      case SortOption.date:
        // 모든 데이터를 가져온 후 클라이언트에서 정렬
        return query.orderBy('timestamp', descending: true);
    }
  }

  // 정렬 옵션 변경 함수
  void _changeSortOption(SortOption option) {
    setState(() {
      _currentSortOption = option;
    });
  }

  // 정렬 메뉴 표시
  void _showSortMenu() {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ListTile(
                title: Text('최신순'),
                selected: _currentSortOption == SortOption.latest,
                onTap: () {
                  _changeSortOption(SortOption.latest);
                  Navigator.pop(context);
                },
              ),
              ListTile(
                title: Text('오래된순'),
                selected: _currentSortOption == SortOption.oldest,
                onTap: () {
                  _changeSortOption(SortOption.oldest);
                  Navigator.pop(context);
                },
              ),
              ListTile(
                title: Text('기록 시간순'),
                selected: _currentSortOption == SortOption.time,
                onTap: () {
                  _changeSortOption(SortOption.time);
                  Navigator.pop(context);
                },
              ),
              ListTile(
                title: Text('날짜별'),
                selected: _currentSortOption == SortOption.date,
                onTap: () {
                  _changeSortOption(SortOption.date);
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  // 정렬 옵션 텍스트 반환
  String _getSortOptionText(SortOption option) {
    switch (option) {
      case SortOption.latest:
        return '최신순';
      case SortOption.oldest:
        return '오래된순';
      case SortOption.time:
        return '기록 시간순';
      case SortOption.date:
        return '날짜별';
    }
  }

  // 키보드 이벤트 처리 함수
  void _handleKeyEvent(RawKeyEvent event) {
    // 텍스트 필드에 포커스가 없을 때만 스페이스바 감지
    if (!_isTextFieldFocused && 
        !_referenceFocusNode.hasFocus && 
        !_meetingDataFocusNode.hasFocus) {
      if (event is RawKeyDownEvent) {
        if (event.logicalKey == LogicalKeyboardKey.space) {
          // 스페이스바가 눌렸을 때 타이머 상태 토글
          if (_isPlaying) {
            _pauseTimer();
          } else {
            _startTimer();
          }
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // 화면 높이 구하기
    final screenHeight = MediaQuery.of(context).size.height;
    final isSmallScreen = screenHeight <= 150;

    return Focus(
      // 전체 화면 포커스 상태 변경 감지
      onFocusChange: (hasFocus) {
        _checkFocusState();
      },
      child: RawKeyboardListener(
        focusNode: _keyboardFocusNode,
        onKey: _handleKeyEvent,
        autofocus: true,
        child: Scaffold(
          // 작은 화면에서는 앱바 숨기기
          appBar: isSmallScreen ? null : AppBar(
            title: Text('Main Page'),
            actions: [
              // 정렬 버튼 추가
              IconButton(
                icon: Icon(Icons.sort),
                onPressed: _showSortMenu,
              ),
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
                                _logout();
                                Navigator.pop(context); // Bottom sheet 닫기
                              },
                            ),
                            ListTile(
                              leading: Icon(Icons.group_add),
                              title: Text('그룹생성'),
                              onTap: () {
                                Navigator.pop(context); // Bottom sheet 닫기
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => CreateGroupPage(),
                                  ),
                                );
                              },
                            ),
                            ListTile(
                              leading: Icon(Icons.person_add),
                              title: Text('그룹참가'),
                              onTap: () {
                                Navigator.pop(context); // Bottom sheet 닫기
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => JoinGroupPage(),
                                  ),
                                );
                              },
                            ),
                            ListTile(
                              leading: Icon(Icons.groups),
                              title: Text('그룹보기'),
                              onTap: () {
                                Navigator.pop(context); // Bottom sheet 닫기
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => GroupListPage(),
                                  ),
                                );
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
          // 작은 화면에서는 배경 투명하게 설정
          backgroundColor: isSmallScreen ? Colors.transparent : null,
          body: GestureDetector(
            // 빈 공간 탭 시 텍스트 필드 포커스 해제
            onTap: () {
              _unfocusTextFields();
            },
            behavior: HitTestBehavior.translucent, // 모든 탭 이벤트 감지
            child: Stack(
              children: [
                // 기록 목록 (작은 화면인 경우 숨김)
                if (!isSmallScreen)
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      children: [
                        // 현재 정렬 기준 표시
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Text(
                                '정렬: ${_getSortOptionText(_currentSortOption)}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Container(
                            color: Colors.white,
                            child: StreamBuilder<QuerySnapshot>(
                              stream: _getSortedQuery().snapshots(),
                              builder: (context, snapshot) {
                                if (snapshot.hasError) {
                                  return Center(child: Text('데이터를 불러오는 중 오류가 발생했습니다.'));
                                }
                                if (snapshot.connectionState == ConnectionState.waiting) {
                                  return Center(child: Text('데이터를 불러오는 중입니다.'));
                                }
                                if (snapshot.data == null || snapshot.data!.docs.isEmpty) {
                                  return Center(child: Text('저장된 데이터가 없습니다.'));
                                }
                                
                                // 클라이언트에서 정렬 처리
                                List<DocumentSnapshot> sortedDocs = List.from(snapshot.data!.docs);
                                
                                if (_currentSortOption == SortOption.time) {
                                  sortedDocs.sort((a, b) {
                                    final aData = a.data() as Map<String, dynamic>;
                                    final bData = b.data() as Map<String, dynamic>;
                                    final aTime = aData['time'] ?? 0;
                                    final bTime = bData['time'] ?? 0;
                                    return bTime.compareTo(aTime); // 내림차순 정렬
                                  });
                                }
                                
                                // 현재 정렬이 날짜별인 경우 날짜별로 그룹화
                                if (_currentSortOption == SortOption.date) {
                                  // 날짜로 정렬
                                  sortedDocs.sort((a, b) {
                                    final aData = a.data() as Map<String, dynamic>;
                                    final bData = b.data() as Map<String, dynamic>;
                                    final aDate = aData['date'] ?? '';
                                    final bDate = bData['date'] ?? '';
                                    final compare = bDate.compareTo(aDate); // 날짜 내림차순
                                    if (compare == 0) {
                                      // 같은 날짜면 시간으로 정렬
                                      final aTime = aData['timeOfDay'] ?? '';
                                      final bTime = bData['timeOfDay'] ?? '';
                                      return bTime.compareTo(aTime);
                                    }
                                    return compare;
                                  });
                                  
                                  Map<String, List<DocumentSnapshot>> groupedByDate = {};
                                  
                                  for (var doc in sortedDocs) {
                                    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
                                    String date = data['date'] ?? '날짜 없음';
                                    
                                    if (!groupedByDate.containsKey(date)) {
                                      groupedByDate[date] = [];
                                    }
                                    groupedByDate[date]!.add(doc);
                                  }
                                  
                                  List<String> sortedDates = groupedByDate.keys.toList()
                                    ..sort((a, b) => b.compareTo(a)); // 최신 날짜가 먼저 오도록
                                  
                                  return ListView.builder(
                                    itemCount: sortedDates.length,
                                    itemBuilder: (context, index) {
                                      String date = sortedDates[index];
                                      List<DocumentSnapshot> docs = groupedByDate[date]!;
                                      
                                      return Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Padding(
                                            padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
                                            child: Text(
                                              date,
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 16,
                                              ),
                                            ),
                                          ),
                                          ...docs.map((doc) {
                                            Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
                                            return InkWell(
                                              onTap: () {
                                                _showEditDialog(
                                                  context, 
                                                  doc.id,
                                                  data['reference'], 
                                                  data['meetingData'],
                                                  date: data['date'],
                                                  timeOfDay: data['timeOfDay'],
                                                );
                                              },
                                              child: ListTile(
                                                title: Text(data['reference'] ?? ''),
                                                subtitle: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(data['meetingData'] ?? ''),
                                                    Text('날짜: ${data['date'] ?? ''} ${data['timeOfDay'] ?? ''}'),
                                                  ],
                                                ),
                                                trailing: Text(
                                                    '${data['time'] ~/ 60}:${(data['time'] % 60).toString().padLeft(2, '0')}'),
                                              ),
                                            );
                                          }).toList(),
                                          Divider(),
                                        ],
                                      );
                                    },
                                  );
                                }
                                // 기본 목록 표시
                                else {
                                  return ListView(
                                    children: sortedDocs.map((document) {
                                      Map<String, dynamic> data = document.data() as Map<String, dynamic>;
                                      return InkWell(
                                        onTap: () {
                                          _showEditDialog(
                                            context, 
                                            document.id,
                                            data['reference'], 
                                            data['meetingData'],
                                            date: data['date'],
                                            timeOfDay: data['timeOfDay'],
                                          );
                                        },
                                        child: ListTile(
                                          title: Text(data['reference'] ?? ''),
                                          subtitle: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(data['meetingData'] ?? ''),
                                              Text('날짜: ${data['date'] ?? ''} ${data['timeOfDay'] ?? ''}'),
                                            ],
                                          ),
                                          trailing: Text(
                                              '${data['time'] ~/ 60}:${(data['time'] % 60).toString().padLeft(2, '0')}'),
                                        ),
                                      );
                                    }).toList(),
                                  );
                                }
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                
                // 타이머 위치 조정 (작은 화면인 경우 화면에 맞게 조정)
                if (isSmallScreen)
                  // 작은 화면일 때는 화면 전체를 사용하여 타이머 표시
                  Container(
                    width: double.infinity, // 가로 화면 꽉 채우기
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: Colors.white,
                        // 그림자 제거
                      ),
                      child: GestureDetector(
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 10),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              // 제목과 부제목 입력 필드 유지
                              Expanded(
                                child: TextField(
                                  focusNode: _referenceFocusNode, // 포커스 노드 할당
                                  controller: _referenceController,
                                  decoration: InputDecoration(
                                      hintText: "제목", border: InputBorder.none),
                                  onChanged: (value) => _reference = value,
                                  onSubmitted: (_) => _unfocusTextFields(),
                                ),
                              ),
                              Expanded(
                                child: TextField(
                                  focusNode: _meetingDataFocusNode, // 포커스 노드 할당
                                  controller: _meetingDataController,
                                  decoration: InputDecoration(
                                      hintText: "부제목", border: InputBorder.none),
                                  onChanged: (value) => _meetingData = value,
                                  onSubmitted: (_) => _unfocusTextFields(),
                                ),
                              ),
                              VerticalDivider(),
                              Padding(padding: EdgeInsets.symmetric(horizontal: 4)),
                              ValueListenableBuilder(
                                valueListenable: _elapsedSecondsNotifier,
                                builder: (context, value, child) {
                                  final minutes = value ~/ 60;
                                  final seconds = (value % 60).toString().padLeft(2, '0');
                                  return Text(
                                    '$minutes:$seconds',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  );
                                },
                              ),
                              Padding(padding: EdgeInsets.symmetric(horizontal: 2)),
                              
                              // 타이머 제어 버튼들
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // 재생/일시정지 버튼
                                  IconButton(
                                    icon: Icon(
                                      _isPlaying ? Icons.pause : Icons.play_arrow,
                                      color: _isPlaying ? Colors.orange : Colors.purple,
                                    ),
                                    onPressed: () {
                                      if (_isPlaying) {
                                        _pauseTimer();
                                      } else {
                                        _startTimer();
                                      }
                                    },
                                  ),
                                  
                                  // 완료 버튼 (정지 및 저장)
                                  IconButton(
                                    icon: Icon(Icons.stop, color: Colors.red),
                                    onPressed: (_isPlaying || _isPaused) ? _stopTimer : null,
                                  ),
                                  
                                  // 취소 버튼 (리셋)
                                  ValueListenableBuilder(
                                    valueListenable: _elapsedSecondsNotifier,
                                    builder: (context, value, _) {
                                      return IconButton(
                                        icon: Icon(Icons.cancel, color: Colors.grey),
                                        onPressed: value > 0 ? _resetTimer : null,
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  )
                else
                  // 일반 화면에서는 기존 스타일 유지
                  Positioned(
                    bottom: isSmallScreen ? null : 20,
                    left: 20,
                    right: 20,
                    top: isSmallScreen ? 0 : null,
                    child: Center(
                      child: Container(
                        height: 50,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color: Colors.white,
                          boxShadow: isSmallScreen ? null : [
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
                                child: Focus(
                                  onFocusChange: (hasFocus) {
                                    setState(() {
                                      _isTextFieldFocused = hasFocus || _meetingDataFocusNode.hasFocus;
                                    });
                                  },
                                  child: TextField(
                                    focusNode: _referenceFocusNode,
                                    controller: _referenceController,
                                    decoration: InputDecoration(
                                        hintText: "제목", border: InputBorder.none),
                                    onChanged: (value) => _reference = value,
                                    onSubmitted: (_) => _unfocusTextFields(),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Focus(
                                  onFocusChange: (hasFocus) {
                                    setState(() {
                                      _isTextFieldFocused = hasFocus || _referenceFocusNode.hasFocus;
                                    });
                                  },
                                  child: TextField(
                                    focusNode: _meetingDataFocusNode,
                                    controller: _meetingDataController,
                                    decoration: InputDecoration(
                                        hintText: "부제목", border: InputBorder.none),
                                    onChanged: (value) => _meetingData = value,
                                    onSubmitted: (_) => _unfocusTextFields(),
                                  ),
                                ),
                              ),
                              VerticalDivider(),
                              Padding(padding: EdgeInsets.symmetric(horizontal: 4)),
                              ValueListenableBuilder(
                                valueListenable: _elapsedSecondsNotifier,
                                builder: (context, value, child) {
                                  final minutes = value ~/ 60;
                                  final seconds = (value % 60).toString().padLeft(2, '0');
                                  return Text(
                                    '$minutes:$seconds',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  );
                                },
                              ),
                              Padding(padding: EdgeInsets.symmetric(horizontal: 2)),
                              
                              // 타이머 제어 버튼들
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // 재생/일시정지 버튼
                                  IconButton(
                                    icon: Icon(
                                      _isPlaying ? Icons.pause : Icons.play_arrow,
                                      color: _isPlaying ? Colors.orange : Colors.purple,
                                    ),
                                    onPressed: () {
                                      if (_isPlaying) {
                                        _pauseTimer();
                                      } else {
                                        _startTimer();
                                      }
                                    },
                                  ),
                                  
                                  // 완료 버튼 (정지 및 저장)
                                  IconButton(
                                    icon: Icon(Icons.stop, color: Colors.red),
                                    onPressed: (_isPlaying || _isPaused) ? _stopTimer : null,
                                  ),
                                  
                                  // 취소 버튼 (리셋)
                                  ValueListenableBuilder(
                                    valueListenable: _elapsedSecondsNotifier,
                                    builder: (context, value, _) {
                                      return IconButton(
                                        icon: Icon(Icons.cancel, color: Colors.grey),
                                        onPressed: value > 0 ? _resetTimer : null,
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
  
  void _unfocusTextFields() {
    _referenceFocusNode.unfocus();
    _meetingDataFocusNode.unfocus();
    FocusScope.of(context).unfocus();
    
    // 명시적 포커스 설정
    FocusScope.of(context).requestFocus(_keyboardFocusNode);
    
    // 포커스 상태 즉시 업데이트
    setState(() {
      _isTextFieldFocused = false;
    });
  }
}

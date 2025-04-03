import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import '../services/auth_service.dart';
import '../models/user_model.dart';
import 'package:window_manager/window_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

class GroupDetailPage extends StatefulWidget {
  final String groupId;
  final String groupName;

  const GroupDetailPage({
    Key? key,
    required this.groupId,
    required this.groupName,
  }) : super(key: key);

  @override
  State<GroupDetailPage> createState() => _GroupDetailPageState();
}

enum SortOption {
  latest, // 최신순
  oldest, // 오래된순
  time, // 기록 시간순
  person, // 사람별
  date, // 날짜별
}

class _GroupDetailPageState extends State<GroupDetailPage>
    with WidgetsBindingObserver {
  final TextEditingController _referenceController = TextEditingController();
  final TextEditingController _meetingDataController = TextEditingController();
  String _reference = '';
  String _meetingData = '';
  Timer? _timer;
  bool _isPlaying = false;
  bool _isPaused = false;
  SortOption _currentSortOption = SortOption.latest;
  final ValueNotifier<int> _elapsedSecondsNotifier = ValueNotifier<int>(0);

  // 인증 서비스
  final AuthService _authService = AuthService();
  
  // 현재 사용자
  UserModel? get _user => _authService.currentUser;

  // 키보드 포커스 노드 추가
  final FocusNode _keyboardFocusNode = FocusNode();
  final FocusNode _referenceFocusNode = FocusNode();
  final FocusNode _meetingDataFocusNode = FocusNode();

  // 텍스트 필드 포커스 상태 추적
  bool _isTextFieldFocused = false;

  // 전역 포커스 변경 감지 구독
  late final StreamSubscription<bool> _focusSubscription;

  // 화면 크기와 고정 상태를 관리하기 위한 변수 추가
  bool _isExpanded = true;
  bool _isAlwaysOnTop = false;  // 기본값을 false로 변경

  // 마지막 상태 로드 시간 추적
  int _lastLoadTime = 0;

  // 화면 확장/축소 전환 함수
  Future<void> _toggleExpand() async {
    try {
      setState(() {
        _isExpanded = !_isExpanded;
      });
      
      // 현재 창 크기 가져오기
      Size currentSize = await windowManager.getSize();
      
      // 창 크기 변경 (너비는 유지)
      if (_isExpanded) {
        await windowManager.setSize(Size(currentSize.width, 600));
      } else {
        await windowManager.setSize(Size(currentSize.width, 80));
      }
    } catch (e) {
      print('화면 크기 변경 중 오류 발생: $e');
      // 오류 발생 시 상태 되돌리기
      setState(() {
        _isExpanded = !_isExpanded;
      });
    }
  }

  // 항상 위에 표시 상태 전환 함수
  Future<void> _toggleAlwaysOnTop() async {
    try {
      setState(() {
        _isAlwaysOnTop = !_isAlwaysOnTop;
      });
      await windowManager.setAlwaysOnTop(_isAlwaysOnTop);
      
      // 상태 저장
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setBool('is_always_on_top', _isAlwaysOnTop);
    } catch (e) {
      print('화면 고정 상태 변경 중 오류 발생: $e');
      // 오류 발생 시 상태 되돌리기
      setState(() {
        _isAlwaysOnTop = !_isAlwaysOnTop;
      });
    }
  }

  // 화면 고정 상태 불러오기
  Future<void> _loadAlwaysOnTopState() async {
    // 너무 자주 호출되는 것 방지 (500ms 이내 호출 무시)
    int now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastLoadTime < 500) return;
    _lastLoadTime = now;
    
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      bool savedPinState = prefs.getBool('is_always_on_top') ?? false;
      
      // 현재 상태와 다를 때만 업데이트
      if (_isAlwaysOnTop != savedPinState) {
        setState(() {
          _isAlwaysOnTop = savedPinState;
        });
        
        await windowManager.setAlwaysOnTop(savedPinState);
      }
    } catch (e) {
      print('상태 불러오기 중 오류 발생: $e');
    }
  }

  // 초기 창 설정 함수
  Future<void> _initializeWindow() async {
    try {
      await windowManager.ensureInitialized();
      
      // SharedPreferences에서 저장된 상태 가져오기
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      bool savedPinState = prefs.getBool('is_always_on_top') ?? false;
      
      setState(() {
        _isAlwaysOnTop = savedPinState;
        _isExpanded = true;  // 기본값은 확장된 상태
      });
      
      // 현재 창 크기 가져오기 (기본값 사용)
      Size currentSize = Size(800, 600);
      
      WindowOptions windowOptions = WindowOptions(
        size: _isExpanded ? Size(currentSize.width, 600) : Size(currentSize.width, 80),
        center: true,
        backgroundColor: Colors.transparent,
        skipTaskbar: false,
      );
      
      await windowManager.waitUntilReadyToShow(windowOptions, () async {
        await windowManager.show();
        await windowManager.focus();
        await windowManager.setAlwaysOnTop(savedPinState);
      });
    } catch (e) {
      print('창 초기화 중 오류 발생: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    _initializeWindow();  // 창 초기화 함수 호출
    
    // 위젯 바인딩 옵저버 등록
    WidgetsBinding.instance.addObserver(this);

    // 포커스 노드 설정 및 감시
    _setupFocusNodes();

    // 전체 키보드 포커스 설정
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FocusScope.of(context).requestFocus(_keyboardFocusNode);
    });
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

    final hasFocus =
        _referenceFocusNode.hasFocus || _meetingDataFocusNode.hasFocus;
    if (hasFocus != _isTextFieldFocused) {
      setState(() {
        _isTextFieldFocused = hasFocus;
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // 앱 상태 변경 시 포커스 확인
    if (state == AppLifecycleState.resumed) {
      _checkFocusState();
      _loadAlwaysOnTopState();  // 앱이 재개될 때 화면 고정 상태 다시 로드
    }
  }

  // 페이지가 다시 보일 때 화면 고정 상태 확인
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadAlwaysOnTopState();  // 페이지가 다시 활성화될 때 화면 고정 상태 다시 로드
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
    // 현재 TextField의 값을 저장
    _reference = _referenceController.text;
    _meetingData = _meetingDataController.text;
    
    setState(() {
      _isPlaying = false;
      _isPaused = false;
    });
    
    // 데이터 저장 후 TextField 초기화
    _saveDataToFirestore().then((_) {
      _referenceController.clear();
      _meetingDataController.clear();
      _reference = "";
      _meetingData = "";
    });
    
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

      // 그룹 기록에 저장
      await FirebaseFirestore.instance
          .collection('groups')
          .doc(widget.groupId)
          .collection('records')
          .add({
        'reference': _reference,
        'meetingData': _meetingData,
        'time': _elapsedSecondsNotifier.value,
        'timestamp': FieldValue.serverTimestamp(),
        'date':
            '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}',
        'timeOfDay':
            '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
        'userId': _user!.uid,
        'userEmail': _user!.email,
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('그룹 기록이 저장되었습니다.')),
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
          .collection('groups')
          .doc(widget.groupId)
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
          .collection('groups')
          .doc(widget.groupId)
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

  void _showEditDialog(
      BuildContext context, String docId, String reference, String meetingData,
      {String? date, String? timeOfDay, String? userEmail}) {
    TextEditingController _referenceController =
        TextEditingController(text: reference);
    TextEditingController _meetingDataController =
        TextEditingController(text: meetingData);

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.white,
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
              if (userEmail != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4.0),
                  child: Text('작성자: $userEmail',
                      style: TextStyle(fontSize: 12, color: Colors.grey)),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                '취소',
                style: TextStyle(color: Colors.black),
              ),
            ),
            TextButton(
              onPressed: () {
                _updateRecord(docId, _referenceController.text,
                    _meetingDataController.text);
                Navigator.pop(context);
              },
              child: Text(
                '수정',
                style: TextStyle(color: Colors.black),
              ),
            ),
            TextButton(
              onPressed: () {
                _deleteRecord(docId);
                Navigator.pop(context);
              },
              child: Text(
                '삭제',
                style: TextStyle(color: Colors.black),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _leaveGroup() async {
    if (_user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('로그인이 필요합니다.')),
      );
      return;
    }

    // 확인 대화상자 표시
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text('그룹 탈퇴'),
        content: Text('정말로 이 그룹에서 탈퇴하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('취소', style: TextStyle(color: Colors.black),),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('탈퇴', style: TextStyle(color: Colors.black),),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      // 그룹 문서 가져오기
      final groupDoc = await FirebaseFirestore.instance
          .collection('groups')
          .doc(widget.groupId)
          .get();

      if (!groupDoc.exists) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('그룹을 찾을 수 없습니다.')),
        );
        return;
      }

      final groupData = groupDoc.data() as Map<String, dynamic>;
      final List<dynamic> members = List.from(groupData['members'] ?? []);
      final String createdBy = groupData['createdBy'] ?? '';

      // 그룹 생성자인 경우 탈퇴 불가 (그룹 삭제 기능 추가 필요)
      if (createdBy == _user!.uid) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('그룹 생성자는 탈퇴할 수 없습니다. 그룹을 삭제하려면 관리자에게 문의하세요.')),
        );
        return;
      }

      // 멤버 목록에서 사용자 제거
      members.remove(_user!.uid);

      // 그룹 문서 업데이트
      await FirebaseFirestore.instance
          .collection('groups')
          .doc(widget.groupId)
          .update({
        'members': members,
      });

      // 사용자의 그룹 목록에서도 제거
      await FirebaseFirestore.instance
          .collection('users')
          .doc(_user!.uid)
          .collection('groups')
          .doc(widget.groupId)
          .delete();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('그룹에서 탈퇴했습니다.')),
      );

      // 그룹 목록 페이지로 돌아가기
      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('그룹 탈퇴에 실패했습니다: $e')),
      );
    }
  }

  @override
  void dispose() {
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
    Query<Map<String, dynamic>> query = FirebaseFirestore.instance
        .collection('groups')
        .doc(widget.groupId)
        .collection('records');

    // 기본적으로 timestamp로만 정렬하고 나머지는 클라이언트에서 처리
    switch (_currentSortOption) {
      case SortOption.latest:
        return query.orderBy('timestamp', descending: true);
      case SortOption.oldest:
        return query.orderBy('timestamp', descending: false);
      case SortOption.time:
      case SortOption.person:
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

  @override
  Widget build(BuildContext context) {
    // 페이지가 화면에 보일 때마다 상태 확인
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadAlwaysOnTopState();
    });
    
    // 화면 높이 구하기
    final screenHeight = MediaQuery.of(context).size.height;
    final isSmallScreen = screenHeight <= 150;

    return Focus(
      onFocusChange: (hasFocus) {
        _checkFocusState();
      },
      child: RawKeyboardListener(
        focusNode: _keyboardFocusNode,
        onKey: _handleKeyEvent,
        autofocus: true,
        child: Scaffold(
          appBar: isSmallScreen
              ? null
              : AppBar(
                  title: Text(widget.groupName),
                  backgroundColor: Color(0xFFF9FAFC),
                  scrolledUnderElevation: 0,
                  shadowColor: Colors.transparent,
                  elevation: 0,
                  forceMaterialTransparency: false,
                  actions: [
                    StreamBuilder<DocumentSnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('groups')
                          .doc(widget.groupId)
                          .snapshots(),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) return SizedBox();
                        
                        return IconButton(
                          icon: Icon(Icons.file_copy_outlined, 
                            color: Colors.black, 
                            size: 20
                          ),
                          onPressed: () async {
                            final groupData = snapshot.data!.data() as Map<String, dynamic>;
                            final joinCode = groupData['joinCode'];
                            if (joinCode != null) {
                              await Clipboard.setData(ClipboardData(text: joinCode));
                              
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text("참여 코드가 복사되었습니다.\n코드: $joinCode"),
                                  duration: Duration(seconds: 2),
                                ),
                              );
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text("참여 코드를 찾을 수 없습니다."),
                                  duration: Duration(seconds: 2),
                                ),
                              );
                            }
                          },
                          tooltip: '참여 코드 복사',
                        );
                      },
                    ),
                    PopupMenuButton<SortOption>(
                      color: Colors.white,
                      icon: Row(
                        children: [
                          Text('정렬 : ${_getSortOptionText(_currentSortOption)}',
                              style:
                                  TextStyle(fontSize: 14, color: Colors.black)),
                          Icon(Icons.arrow_drop_down, color: Colors.black),
                        ],
                      ),
                      onSelected: (SortOption option) {
                        _changeSortOption(option);
                      },
                      itemBuilder: (BuildContext context) =>
                          <PopupMenuEntry<SortOption>>[
                        PopupMenuItem<SortOption>(
                          value: SortOption.latest,
                          child: Text('최신순',
                              style: TextStyle(color: Colors.black)),
                        ),
                        PopupMenuItem<SortOption>(
                          value: SortOption.oldest,
                          child: Text('오래된순',
                              style: TextStyle(color: Colors.black)),
                        ),
                        PopupMenuItem<SortOption>(
                          value: SortOption.time,
                          child: Text('기록 시간순',
                              style: TextStyle(color: Colors.black)),
                        ),
                        PopupMenuItem<SortOption>(
                          value: SortOption.person,
                          child: Text('사람별',
                              style: TextStyle(color: Colors.black)),
                        ),
                        PopupMenuItem<SortOption>(
                          value: SortOption.date,
                          child: Text('날짜별',
                              style: TextStyle(color: Colors.black)),
                        ),
                      ],
                    ),
                    PopupMenuButton<String>(
                      color: Colors.white,
                      onSelected: (value) {
                        if (value == 'leave') {
                          _leaveGroup();
                        }
                      },
                      itemBuilder: (BuildContext context) =>
                          <PopupMenuEntry<String>>[
                        PopupMenuItem<String>(
                          value: 'leave',
                          child: Row(
                            children: [
                              Icon(Icons.exit_to_app, color: Colors.red),
                              SizedBox(width: 8),
                              Text('그룹 탈퇴',
                                  style: TextStyle(color: Colors.red)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
          backgroundColor:
              isSmallScreen ? Colors.transparent : Color(0xFFF9FAFC),
          body: GestureDetector(
            onTap: () {
              _unfocusTextFields();
            },
            behavior: HitTestBehavior.translucent,
            child: Stack(
              children: [
                if (!isSmallScreen)
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      children: [
                        Expanded(
                          child: Container(
                            color: Colors.white,
                            child: StreamBuilder<QuerySnapshot>(
                              stream: _getSortedQuery().snapshots(),
                              builder: (context, snapshot) {
                                if (snapshot.hasError) {
                                  return Center(
                                      child: Text('데이터를 불러오는 중 오류가 발생했습니다.'));
                                }
                                if (snapshot.connectionState ==
                                    ConnectionState.waiting) {
                                  return Center(
                                      child: CircularProgressIndicator());
                                }
                                if (snapshot.data == null ||
                                    snapshot.data!.docs.isEmpty) {
                                  return Center(child: Text('저장된 기록이 없습니다.'));
                                }

                                // 클라이언트에서 정렬 처리
                                List<DocumentSnapshot> sortedDocs =
                                    List.from(snapshot.data!.docs);

                                if (_currentSortOption == SortOption.time) {
                                  sortedDocs.sort((a, b) {
                                    final aData =
                                        a.data() as Map<String, dynamic>;
                                    final bData =
                                        b.data() as Map<String, dynamic>;
                                    final aTime = aData['time'] ?? 0;
                                    final bTime = bData['time'] ?? 0;
                                    return bTime.compareTo(aTime); // 내림차순 정렬
                                  });
                                }

                                // 현재 정렬이 날짜별인 경우 날짜별로 그룹화
                                if (_currentSortOption == SortOption.date) {
                                  // 날짜로 정렬
                                  sortedDocs.sort((a, b) {
                                    final aData =
                                        a.data() as Map<String, dynamic>;
                                    final bData =
                                        b.data() as Map<String, dynamic>;
                                    final aDate = aData['date'] ?? '';
                                    final bDate = bData['date'] ?? '';
                                    final compare =
                                        bDate.compareTo(aDate); // 날짜 내림차순
                                    if (compare == 0) {
                                      // 같은 날짜면 시간으로 정렬
                                      final aTime = aData['timeOfDay'] ?? '';
                                      final bTime = bData['timeOfDay'] ?? '';
                                      return bTime.compareTo(aTime);
                                    }
                                    return compare;
                                  });

                                  Map<String, List<DocumentSnapshot>>
                                      groupedByDate = {};

                                  for (var doc in sortedDocs) {
                                    Map<String, dynamic> data =
                                        doc.data() as Map<String, dynamic>;
                                    String date = data['date'] ?? '날짜 없음';

                                    if (!groupedByDate.containsKey(date)) {
                                      groupedByDate[date] = [];
                                    }
                                    groupedByDate[date]!.add(doc);
                                  }

                                  List<String> sortedDates = groupedByDate.keys
                                      .toList()
                                    ..sort((a, b) =>
                                        b.compareTo(a)); // 최신 날짜가 먼저 오도록

                                  return ListView.builder(
                                    itemCount: sortedDates.length,
                                    itemBuilder: (context, index) {
                                      String date = sortedDates[index];
                                      List<DocumentSnapshot> docs =
                                          groupedByDate[date]!;

                                      return Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Padding(
                                            padding: const EdgeInsets.symmetric(
                                                vertical: 8.0,
                                                horizontal: 16.0),
                                            child: Text(
                                              date,
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 16,
                                              ),
                                            ),
                                          ),
                                          ...docs.map((doc) =>
                                              _buildListTile(doc, _user)),
                                          Divider(),
                                        ],
                                      );
                                    },
                                  );
                                }
                                // 현재 정렬이 사람별인 경우 사람별로 그룹화
                                else if (_currentSortOption ==
                                    SortOption.person) {
                                  // 사람별로 정렬
                                  sortedDocs.sort((a, b) {
                                    final aData =
                                        a.data() as Map<String, dynamic>;
                                    final bData =
                                        b.data() as Map<String, dynamic>;
                                    final aEmail = aData['userEmail'] ?? '';
                                    final bEmail = bData['userEmail'] ?? '';
                                    final compare =
                                        aEmail.compareTo(bEmail); // 이메일 오름차순
                                    if (compare == 0) {
                                      // 같은 사람이면 시간순으로 정렬
                                      final aTime =
                                          aData['timestamp'] ?? Timestamp.now();
                                      final bTime =
                                          bData['timestamp'] ?? Timestamp.now();
                                      return bTime.compareTo(aTime); // 최신순
                                    }
                                    return compare;
                                  });

                                  Map<String, List<DocumentSnapshot>>
                                      groupedByPerson = {};

                                  for (var doc in sortedDocs) {
                                    Map<String, dynamic> data =
                                        doc.data() as Map<String, dynamic>;
                                    String person =
                                        data['userEmail'] ?? '알 수 없음';

                                    if (!groupedByPerson.containsKey(person)) {
                                      groupedByPerson[person] = [];
                                    }
                                    groupedByPerson[person]!.add(doc);
                                  }

                                  List<String> sortedPersons =
                                      groupedByPerson.keys.toList()..sort();

                                  return ListView.builder(
                                    itemCount: sortedPersons.length,
                                    itemBuilder: (context, index) {
                                      String person = sortedPersons[index];
                                      List<DocumentSnapshot> docs =
                                          groupedByPerson[person]!;

                                      return Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Padding(
                                            padding: const EdgeInsets.symmetric(
                                                vertical: 8.0,
                                                horizontal: 16.0),
                                            child: Text(
                                              person,
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 16,
                                              ),
                                            ),
                                          ),
                                          ...docs.map((doc) =>
                                              _buildListTile(doc, _user)),
                                          Divider(),
                                        ],
                                      );
                                    },
                                  );
                                }
                                // 기본 목록 표시
                                else {
                                  return ListView(
                                    children: sortedDocs
                                        .map((doc) => _buildListTile(doc, _user))
                                        .toList(),
                                  );
                                }
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (isSmallScreen)
                  Container(
                    width: double.infinity,
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: Colors.white,
                      ),
                      child: Focus(
                        onFocusChange: (hasFocus) {
                          _checkFocusState();
                        },
                        child: GestureDetector(
                          child: Padding(
                            padding: EdgeInsets.symmetric(horizontal: 10),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(
                                  child: Focus(
                                    onFocusChange: (hasFocus) {
                                      setState(() {
                                        _isTextFieldFocused = hasFocus ||
                                            _meetingDataFocusNode.hasFocus;
                                      });
                                    },
                                    child: TextField(
                                      focusNode: _referenceFocusNode,
                                      controller: _referenceController,
                                      decoration: InputDecoration(
                                          hintText: "제목",
                                          border: InputBorder.none),
                                      onChanged: (value) => _reference = value,
                                      onSubmitted: (_) => _unfocusTextFields(),
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Focus(
                                    onFocusChange: (hasFocus) {
                                      setState(() {
                                        _isTextFieldFocused = hasFocus ||
                                            _referenceFocusNode.hasFocus;
                                      });
                                    },
                                    child: TextField(
                                      focusNode: _meetingDataFocusNode,
                                      controller: _meetingDataController,
                                      decoration: InputDecoration(
                                          hintText: "부제목",
                                          border: InputBorder.none),
                                      onChanged: (value) =>
                                          _meetingData = value,
                                      onSubmitted: (_) => _unfocusTextFields(),
                                    ),
                                  ),
                                ),
                                VerticalDivider(),
                                Padding(
                                    padding:
                                        EdgeInsets.symmetric(horizontal: 4)),
                                ValueListenableBuilder(
                                  valueListenable: _elapsedSecondsNotifier,
                                  builder: (context, value, child) {
                                    final minutes = value ~/ 60;
                                    final seconds =
                                        (value % 60).toString().padLeft(2, '0');
                                    return Text(
                                      '$minutes:$seconds',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    );
                                  },
                                ),
                                Padding(
                                    padding:
                                        EdgeInsets.symmetric(horizontal: 2)),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: Icon(
                                        _isExpanded ? Icons.expand_more : Icons.expand_less,
                                        color: Colors.blue,
                                      ),
                                      onPressed: _toggleExpand,
                                    ),
                                    IconButton(
                                      icon: Icon(
                                        _isAlwaysOnTop ? Icons.push_pin : Icons.push_pin_outlined,
                                        color: _isAlwaysOnTop ? Colors.orange : Colors.grey,
                                      ),
                                      onPressed: _toggleAlwaysOnTop,
                                    ),
                                    IconButton(
                                      icon: Icon(
                                        _isPlaying
                                            ? Icons.pause
                                            : Icons.play_arrow,
                                        color: _isPlaying
                                            ? Colors.orange
                                            : Colors.purple,
                                      ),
                                      onPressed: () {
                                        if (_isPlaying) {
                                          _pauseTimer();
                                        } else {
                                          _startTimer();
                                        }
                                      },
                                    ),
                                    IconButton(
                                      icon: Icon(Icons.stop, color: Colors.red),
                                      onPressed: (_isPlaying || _isPaused)
                                          ? _stopTimer
                                          : null,
                                    ),
                                    ValueListenableBuilder(
                                      valueListenable: _elapsedSecondsNotifier,
                                      builder: (context, value, _) {
                                        return IconButton(
                                          icon: Icon(Icons.cancel,
                                              color: Colors.grey),
                                          onPressed:
                                              value > 0 ? _resetTimer : null,
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
                  )
                else
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
                              child: Focus(
                                onFocusChange: (hasFocus) {
                                  setState(() {
                                    _isTextFieldFocused = hasFocus ||
                                        _meetingDataFocusNode.hasFocus;
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
                                    _isTextFieldFocused = hasFocus ||
                                        _referenceFocusNode.hasFocus;
                                  });
                                },
                                child: TextField(
                                  focusNode: _meetingDataFocusNode,
                                  controller: _meetingDataController,
                                  decoration: InputDecoration(
                                      hintText: "부제목",
                                      border: InputBorder.none),
                                  onChanged: (value) => _meetingData = value,
                                  onSubmitted: (_) => _unfocusTextFields(),
                                ),
                              ),
                            ),
                            VerticalDivider(),
                            Padding(
                                padding: EdgeInsets.symmetric(horizontal: 4)),
                            ValueListenableBuilder(
                              valueListenable: _elapsedSecondsNotifier,
                              builder: (context, value, child) {
                                final minutes = value ~/ 60;
                                final seconds =
                                    (value % 60).toString().padLeft(2, '0');
                                return Text(
                                  '$minutes:$seconds',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                );
                              },
                            ),
                            Padding(
                                padding: EdgeInsets.symmetric(horizontal: 2)),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: Icon(
                                    _isExpanded ? Icons.expand_more : Icons.expand_less,
                                    color: Colors.blue,
                                  ),
                                  onPressed: _toggleExpand,
                                ),
                                IconButton(
                                  icon: Icon(
                                    _isAlwaysOnTop ? Icons.push_pin : Icons.push_pin_outlined,
                                    color: _isAlwaysOnTop ? Colors.orange : Colors.grey,
                                  ),
                                  onPressed: _toggleAlwaysOnTop,
                                ),
                                IconButton(
                                  icon: Icon(
                                    _isPlaying ? Icons.pause : Icons.play_arrow,
                                    color: _isPlaying
                                        ? Colors.orange
                                        : Colors.purple,
                                  ),
                                  onPressed: () {
                                    if (_isPlaying) {
                                      _pauseTimer();
                                    } else {
                                      _startTimer();
                                    }
                                  },
                                ),
                                IconButton(
                                  icon: Icon(Icons.stop, color: Colors.red),
                                  onPressed: (_isPlaying || _isPaused)
                                      ? _stopTimer
                                      : null,
                                ),
                                ValueListenableBuilder(
                                  valueListenable: _elapsedSecondsNotifier,
                                  builder: (context, value, _) {
                                    return IconButton(
                                      icon: Icon(Icons.cancel,
                                          color: Colors.grey),
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
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _getSortOptionText(SortOption option) {
    switch (option) {
      case SortOption.latest:
        return '최신순';
      case SortOption.oldest:
        return '오래된순';
      case SortOption.time:
        return '기록 시간순';
      case SortOption.person:
        return '사람별';
      case SortOption.date:
        return '날짜별';
    }
  }

  Widget _buildListTile(DocumentSnapshot document, UserModel? user) {
    Map<String, dynamic> data = document.data() as Map<String, dynamic>;
    final isMyRecord = data['userId'] == user?.uid;

    return ListTile(
      title: Text(data['reference'] ?? ''),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(data['meetingData'] ?? ''),
          Text('작성자: ${data['userEmail'] ?? '알 수 없음'}'),
          Text('날짜: ${data['date'] ?? ''} ${data['timeOfDay'] ?? ''}'),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
              '${data['time'] ~/ 60}:${(data['time'] % 60).toString().padLeft(2, '0')}'),
          if (isMyRecord)
            IconButton(
              icon: Icon(Icons.edit, size: 18),
              onPressed: () {
                _showEditDialog(
                  context,
                  document.id,
                  data['reference'],
                  data['meetingData'],
                  date: data['date'],
                  timeOfDay: data['timeOfDay'],
                  userEmail: data['userEmail'],
                );
              },
            ),
        ],
      ),
      onTap: isMyRecord
          ? () {
              _showEditDialog(
                context,
                document.id,
                data['reference'],
                data['meetingData'],
                date: data['date'],
                timeOfDay: data['timeOfDay'],
                userEmail: data['userEmail'],
              );
            }
          : null,
    );
  }
}

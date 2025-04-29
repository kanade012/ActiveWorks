import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import '../services/auth_service.dart';
import '../models/user_model.dart';
import 'package:window_manager/window_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

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
  final ValueNotifier<int> _totalTimeNotifier = ValueNotifier<int>(0);
  
  // 목표 시간 관련 변수
  final ValueNotifier<int> _dailyGoalMinutesNotifier = ValueNotifier<int>(0);
  final ValueNotifier<int> _todayTotalTimeNotifier = ValueNotifier<int>(0);
  final TextEditingController _goalMinutesController = TextEditingController();
  
  // 회고 관련 변수
  final TextEditingController _reflectionController = TextEditingController();
  String _todayDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
  int _reflectionRating = 0; // 회고 별점 (1~5)
  
  // 회고 필터 관련 변수
  String _currentReflectionFilter = 'all'; // 'all', 'last7', 'last30', 'team'
  String? _teamMemberFilter; // 팀원 필터링용 (null이면 필터링 안함)
  
  // 회고 표시 여부
  bool _showReflectionPanel = true; // 항상 표시되도록 true로 변경
  
  // 인증 서비스
  final AuthService _authService = AuthService();
  
  // 현재 사용자
  UserModel? get _user => _authService.currentUser;

  // 키보드 포커스 노드 추가
  final FocusNode _keyboardFocusNode = FocusNode();
  final FocusNode _referenceFocusNode = FocusNode();
  final FocusNode _meetingDataFocusNode = FocusNode();
  final FocusNode _reflectionFocusNode = FocusNode();
  final FocusNode _goalMinutesFocusNode = FocusNode();

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
        await windowManager.setSize(Size(currentSize.width, 50));
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
      
      // 현재 창 크기 가져오기
      Size currentSize = await windowManager.getSize();
      
      // 창 크기 변경 없이 항상 위에 표시 상태만 변경
      await windowManager.setAlwaysOnTop(savedPinState);
    } catch (e) {
      print('창 초기화 중 오류 발생: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    _initializeWindow();  // 창 초기화 함수 호출
    _loadTotalTime();  // 총 기록 시간 로드
    _loadTodayTime();  // 오늘의 기록 시간 로드
    _loadDailyGoal();  // 목표 시간 로드
    _loadTodayReflection();  // 오늘의 회고 로드
    _recordGroupAccess();  // 그룹 접속 시간 기록
    
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
    _reflectionFocusNode.addListener(_checkFocusState);
    _goalMinutesFocusNode.addListener(_checkFocusState);

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
        _referenceFocusNode.hasFocus || _meetingDataFocusNode.hasFocus ||
        _reflectionFocusNode.hasFocus || _goalMinutesFocusNode.hasFocus;
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
      final currentTime = _elapsedSecondsNotifier.value;
      final String today = DateFormat('yyyy-MM-dd').format(now);

      // 그룹 기록에 저장
      await FirebaseFirestore.instance
          .collection('groups')
          .doc(widget.groupId)
          .collection('records')
          .add({
        'reference': _reference,
        'meetingData': _meetingData,
        'time': currentTime,
        'timestamp': FieldValue.serverTimestamp(),
        'date': today,
        'timeOfDay':
            '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
        'userEmail': _user!.email,
        'userId': _user!.uid,
      });

      // 총 시간 업데이트
      _totalTimeNotifier.value += currentTime;
      
      // 오늘의 기록 시간 업데이트
      if (today == _todayDate) {
        _todayTotalTimeNotifier.value += currentTime;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('데이터가 저장되었습니다.')),
      );
      
      // 텍스트 필드 초기화
      setState(() {
        _reference = "";
        _meetingData = "";
      });
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
      // 삭제할 문서의 시간 정보 가져오기
      final docSnapshot = await FirebaseFirestore.instance
          .collection('groups')
          .doc(widget.groupId)
          .collection('records')
          .doc(docId)
          .get();

      if (docSnapshot.exists) {
        final data = docSnapshot.data() as Map<String, dynamic>;
        final int timeToSubtract = (data['time'] ?? 0).round();
        final String recordDate = data['date'] ?? '';

        // 문서 삭제
        await FirebaseFirestore.instance
            .collection('groups')
            .doc(widget.groupId)
            .collection('records')
            .doc(docId)
            .delete();

        // 총 시간에서 삭제한 시간 빼기
        final int newTotal = _totalTimeNotifier.value - timeToSubtract;
        _totalTimeNotifier.value = newTotal;
        
        // 삭제한 기록이 오늘 날짜인 경우 오늘의 기록 시간도 감소
        if (recordDate == _todayDate) {
          final int newTodayTotal = _todayTotalTimeNotifier.value - timeToSubtract;
          _todayTotalTimeNotifier.value = newTodayTotal;
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('데이터가 삭제되었습니다.')),
        );
      }
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
    _totalTimeNotifier.dispose();
    _keyboardFocusNode.dispose();
    _referenceFocusNode.removeListener(_checkFocusState);
    _referenceFocusNode.dispose();
    _meetingDataFocusNode.removeListener(_checkFocusState);
    _meetingDataFocusNode.dispose();
    _reflectionFocusNode.removeListener(_checkFocusState);
    _reflectionFocusNode.dispose();
    _goalMinutesFocusNode.removeListener(_checkFocusState);
    _goalMinutesFocusNode.dispose();
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

  // 키보드 이벤트 처리
  void _handleKeyEvent(RawKeyEvent event) {
    // 텍스트 필드에 포커스가 없을 때만 스페이스바 감지
    if (!_isTextFieldFocused && !_referenceFocusNode.hasFocus) {
      if (event is RawKeyDownEvent) {
        try {
          // 한국어 입력 처리를 위해 물리적 키와 반복 이벤트 검사 추가
          if (event.logicalKey == LogicalKeyboardKey.space && 
              !event.repeat && // 반복 이벤트 무시
              event.character != 'ㅅ') { // 한국어 자음 입력 무시
            // 스페이스바가 눌렸을 때 타이머 상태 토글
            if (_isPlaying) {
              _pauseTimer();
            } else {
              _startTimer();
            }
          }
        } catch (e) {
          print('키보드 이벤트 처리 중 오류 발생: $e');
        }
      }
    }
  }

  void _unfocusTextFields() {
    _referenceFocusNode.unfocus();
    _meetingDataFocusNode.unfocus();
    _reflectionFocusNode.unfocus();
    _goalMinutesFocusNode.unfocus();
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
              : PreferredSize(
            preferredSize: Size.fromHeight(70),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    AppBar(
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
                  ],
                ),
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
                        Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: ValueListenableBuilder(
                            valueListenable: _totalTimeNotifier,
                            builder: (context, value, child) {
                              return Padding(
                                padding: const EdgeInsets.only(right: 16.0, top: 8.0),
                                child: Text(
                                  "총 기록 시간 : ${_formatTime(value)}",
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        Container(
                          width: double.infinity,
                          height: 100,
                          margin: EdgeInsets.only(bottom: 10),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.grey.withOpacity(0.3),
                                spreadRadius: 1,
                                blurRadius: 3,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: EdgeInsets.only(left: 16, top: 8, bottom: 4),
                                child: Text(
                                  "멤버의 첫 접속 시간",
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: StreamBuilder<DocumentSnapshot>(
                                  stream: FirebaseFirestore.instance
                                      .collection('groups')
                                      .doc(widget.groupId)
                                      .snapshots(),
                                  builder: (context, snapshot) {
                                    if (!snapshot.hasData || snapshot.data == null) {
                                      return Center(child: Text('로딩 중...'));
                                    }
                                    
                                    final groupData = snapshot.data!.data() as Map<String, dynamic>?;
                                    if (groupData == null) {
                                      return Center(child: Text('그룹 정보를 불러올 수 없습니다.'));
                                    }
                                    
                                    final List<dynamic> memberIds = List.from(groupData['members'] ?? []);
                                    if (memberIds.isEmpty) {
                                      return Center(child: Text('멤버가 없습니다.'));
                                    }
                                    
                                    return FutureBuilder<Map<String, dynamic>>(
                                      future: _getMembersFirstAccessTime(memberIds),
                                      builder: (context, accessTimeSnapshot) {
                                        if (!accessTimeSnapshot.hasData) {
                                          return Center(child: CircularProgressIndicator());
                                        }
                                        
                                        final membersData = accessTimeSnapshot.data!;
                                        if (membersData.isEmpty) {
                                          return Center(child: Text('접속 시간 정보가 없습니다.'));
                                        }
                                        
                                        return ListView.builder(
                                          scrollDirection: Axis.horizontal,
                                          itemCount: membersData.length,
                                          itemBuilder: (context, index) {
                                            final email = membersData.keys.elementAt(index);
                                            final accessTime = membersData[email];
                                            
                                            return Container(
                                              margin: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                              decoration: BoxDecoration(
                                                color: Colors.grey.shade100,
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              child: Column(
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    email,
                                                    style: TextStyle(
                                                      fontWeight: FontWeight.bold,
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                  SizedBox(height: 2),
                                                  Text(
                                                    accessTime == null 
                                                        ? '접속 기록 없음' 
                                                        : _formatDateTime(accessTime),
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      color: Colors.grey.shade700,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            );
                                          },
                                        );
                                      },
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Container(
                            color: Colors.white,
                            child: Column(
                              children: [
                                // 목표 시간 및 진행률 표시
                                Container(
                                  padding: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            '오늘의 목표',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                            ),
                                          ),
                                          Row(
                                            children: [
                                              IconButton(
                                                icon: Icon(Icons.history, size: 20),
                                                tooltip: '지난 목표 보기',
                                                onPressed: _showPastGoals,
                                              ),
                                              IconButton(
                                                icon: Icon(Icons.edit, size: 20),
                                                tooltip: '목표 설정',
                                                onPressed: _showGoalSettingDialog,
                                              ),
                                              IconButton(
                                                icon: Icon(Icons.note_alt_outlined, size: 20),
                                                tooltip: '회고 토글',
                                                onPressed: null, // 토글 기능 비활성화
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                      SizedBox(height: 4),
                                      Row(
                                        children: [
                                          ValueListenableBuilder(
                                            valueListenable: _dailyGoalMinutesNotifier,
                                            builder: (context, goalMinutes, _) {
                                              return ValueListenableBuilder(
                                                valueListenable: _todayTotalTimeNotifier,
                                                builder: (context, todaySeconds, _) {
                                                  final todayMinutes = todaySeconds ~/ 60;
                                                  final progress = goalMinutes > 0 
                                                      ? (todayMinutes / goalMinutes * 100).clamp(0.0, 100.0) 
                                                      : 0.0;
                                                  
                                                  return Expanded(
                                                    child: Column(
                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                                      children: [
                                                        Text(
                                                          '목표: ${goalMinutes}분 / 현재: ${todayMinutes}분 (${progress.toStringAsFixed(1)}%)',
                                                          style: TextStyle(fontSize: 14),
                                                        ),
                                                        SizedBox(height: 4),
                                                        LinearProgressIndicator(
                                                          value: progress / 100,
                                                          backgroundColor: Colors.grey.shade200,
                                                          color: _getProgressColor(progress),
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
                                    ],
                                  ),
                                ),
                                
                                // 구분선
                                Divider(),
                                
                                // 기록 목록
                                Expanded(
                                  child: SingleChildScrollView(
                                    child: Column(
                                      children: [
                                        // 기록 목록 영역 - 고정된 크기로 설정하고 내부에서만 스크롤
                                        Container(
                                          height: 300, // 고정 높이 설정
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
                                                      b.compareTo(a));

                                                // 스크롤 가능한 리스트뷰 사용
                                                return ListView.builder(
                                                  itemCount: sortedDates.length,
                                                  itemBuilder: (context, index) {
                                                    String date = sortedDates[index];
                                                    List<DocumentSnapshot> docs = groupedByDate[date]!;

                                                    return Column(
                                                      crossAxisAlignment: CrossAxisAlignment.start,
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
                                                        ...docs.map((doc) {
                                                          Map<String, dynamic> data = doc
                                                              .data() as Map<String, dynamic>;
                                                          return InkWell(
                                                            highlightColor: Colors.transparent,
                                                            hoverColor: Colors.transparent,
                                                            splashColor: Colors.transparent,
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
                                                              trailing: Text('${data['time'] ~/ 60}:${(data['time'] % 60).toString().padLeft(2, '0')}'),
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
                                              return ListView.builder(
                                                itemCount: sortedDocs.length,
                                                itemBuilder: (context, index) {
                                                  DocumentSnapshot document = sortedDocs[index];
                                                  Map<String, dynamic> data = document.data() as Map<String, dynamic>;
                                                  return InkWell(
                                                    highlightColor: Colors.transparent,
                                                    hoverColor: Colors.transparent,
                                                    splashColor: Colors.transparent,
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
                                                      trailing: Text('${data['time'] ~/ 60}:${(data['time'] % 60).toString().padLeft(2, '0')}'),
                                                    ),
                                                  );
                                                },
                                              );
                                            },
                                          ),
                                        ),
                                        
                                        // 회고 패널
                                        SizedBox(height: 16),
                                        Container(
                                          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                children: [
                                                  Text(
                                                    '오늘의 회고',
                                                    style: TextStyle(
                                                      fontWeight: FontWeight.bold,
                                                      fontSize: 16,
                                                    ),
                                                  ),
                                                  Row(
                                                    children: [
                                                      IconButton(
                                                        icon: Icon(Icons.history, size: 20),
                                                        tooltip: '지난 회고 보기',
                                                        onPressed: _showPastReflections,
                                                      ),
                                                      IconButton(
                                                        icon: Icon(Icons.save, size: 20),
                                                        tooltip: '회고 저장',
                                                        onPressed: () {
                                                          _saveTodayReflection(_reflectionController.text);
                                                        },
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                              
                                              // 별점 입력 UI 추가
                                              Padding(
                                                padding: const EdgeInsets.symmetric(vertical: 8.0),
                                                child: Row(
                                                  children: [
                                                    Text('별점: ', style: TextStyle(fontWeight: FontWeight.bold)),
                                                    _buildRatingBar(_reflectionRating.toDouble(), false),
                                                  ],
                                                ),
                                              ),
                                              
                                              SizedBox(height: 8),
                                              Container(
                                                height: 100,
                                                padding: EdgeInsets.symmetric(horizontal: 12),
                                                decoration: BoxDecoration(
                                                  border: Border.all(color: Colors.grey.shade300),
                                                  borderRadius: BorderRadius.circular(8),
                                                ),
                                                child: TextField(
                                                  controller: _reflectionController,
                                                  focusNode: _reflectionFocusNode,
                                                  maxLines: 4,
                                                  decoration: InputDecoration(
                                                    hintText: '오늘의 작업에 대한 회고를 작성하세요...',
                                                    border: InputBorder.none,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        SizedBox(height: 70), // 하단 여백 추가
                                      ],
                                    ),
                                  ),
                                ),
                              ],
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
                                Padding(padding: EdgeInsets.symmetric(horizontal: 30)),
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

  // 총 기록 시간을 로드하는 함수
  Future<void> _loadTotalTime() async {
    if (_user == null) return;
    
    try {
      final querySnapshot = await FirebaseFirestore.instance
          .collection('groups')
          .doc(widget.groupId)
          .collection('records')
          .get();
      
      int totalSeconds = 0;
      for (var doc in querySnapshot.docs) {
        Map<String, dynamic> data = doc.data();
        // 명시적으로 정수로 변환
        final int seconds = (data['time'] ?? 0).round();
        totalSeconds += seconds;
      }
      
      _totalTimeNotifier.value = totalSeconds;
    } catch (e) {
      print('총 기록 시간 로드 중 오류 발생: $e');
    }
  }

  // 시간 포맷 함수
  String _formatTime(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final remainingSeconds = seconds % 60;
    
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
    } else {
      return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
    }
  }

  // 그룹 접속 시간 기록 함수
  Future<void> _recordGroupAccess() async {
    if (_user == null) return;
    
    try {
      // 그룹 접속 기록 저장
      await FirebaseFirestore.instance
          .collection('groups')
          .doc(widget.groupId)
          .collection('access_logs')
          .add({
        'userId': _user!.uid,
        'userEmail': _user!.email,
        'timestamp': FieldValue.serverTimestamp(),
      });
      
      print('그룹 접속 시간 기록 완료');
    } catch (e) {
      print('그룹 접속 시간 기록 오류: $e');
    }
  }

  Future<Map<String, dynamic>> _getMembersFirstAccessTime(List<dynamic> memberIds) async {
    Map<String, dynamic> membersData = {};
    
    // 현재 시간과 오전 9시 기준 시간 계산
    final now = DateTime.now();
    final today9am = DateTime(now.year, now.month, now.day, 9, 0);
    final yesterday9am = today9am.subtract(Duration(days: 1));
    
    // 현재 시각이 오전 9시 이후인지 확인
    final isAfter9am = now.hour >= 9;
    
    // 기준 시간 설정
    final startTime = isAfter9am ? today9am : yesterday9am;
    
    // 각 멤버의 사용자 정보 가져오기
    for (var id in memberIds) {
      try {
        // 먼저 사용자 정보 가져오기
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(id)
            .get();
        
        if (userDoc.exists) {
          final userData = userDoc.data();
          final String email = userData?['email'] ?? '사용자 정보 없음';
          
          // 접속 로그에서 해당 사용자의 기록 찾기
          final accessLogsSnapshot = await FirebaseFirestore.instance
              .collection('groups')
              .doc(widget.groupId)
              .collection('access_logs')
              .where('userId', isEqualTo: id)
              .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(startTime))
              .where('timestamp', isLessThanOrEqualTo: Timestamp.fromDate(now))
              .get();
          
          if (accessLogsSnapshot.docs.isNotEmpty) {
            // 클라이언트 측에서 정렬하여 첫 번째 항목 가져오기
            final sortedDocs = accessLogsSnapshot.docs
                .map((doc) => doc.data())
                .toList()
                ..sort((a, b) {
                  final aTimestamp = a['timestamp'] as Timestamp?;
                  final bTimestamp = b['timestamp'] as Timestamp?;
                  if (aTimestamp == null) return 1;
                  if (bTimestamp == null) return -1;
                  return aTimestamp.compareTo(bTimestamp); // 오름차순 정렬
                });
            
            if (sortedDocs.isNotEmpty && sortedDocs.first['timestamp'] != null) {
              membersData[email] = sortedDocs.first['timestamp'].toDate();
            } else {
              membersData[email] = null;
            }
          } else {
            // 이전 방식으로 시도 - 레코드에서 찾기
            final recordsSnapshot = await FirebaseFirestore.instance
                .collection('groups')
                .doc(widget.groupId)
                .collection('records')
                .where('userId', isEqualTo: id)
                .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(startTime))
                .where('timestamp', isLessThanOrEqualTo: Timestamp.fromDate(now))
                .get();
            
            if (recordsSnapshot.docs.isNotEmpty) {
              final sortedDocs = recordsSnapshot.docs
                  .map((doc) => doc.data())
                  .toList()
                  ..sort((a, b) {
                    final aTimestamp = a['timestamp'] as Timestamp?;
                    final bTimestamp = b['timestamp'] as Timestamp?;
                    if (aTimestamp == null) return 1;
                    if (bTimestamp == null) return -1;
                    return aTimestamp.compareTo(bTimestamp);
                  });
              
              if (sortedDocs.isNotEmpty && sortedDocs.first['timestamp'] != null) {
                membersData[email] = sortedDocs.first['timestamp'].toDate();
              } else {
                membersData[email] = null;
              }
            } else {
              membersData[email] = null;
            }
          }
        }
      } catch (e) {
        print('멤버 정보 가져오기 오류: $e');
      }
    }
    
    // 현재 사용자의 현재 접속을 데이터에 추가
    if (_user != null && _user!.email != null) {
      if (!membersData.containsKey(_user!.email)) {
        membersData[_user!.email!] = DateTime.now();
      }
    }
    
    return membersData;
  }

  String _formatDateTime(DateTime dateTime) {
    // 시간과 분을 두 자리 숫자로 포맷팅
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return '${hour}시:${minute}분';
  }

  // 오늘의 목표 시간 로드
  Future<void> _loadDailyGoal() async {
    if (_user == null) return;
    
    try {
      final goalDoc = await FirebaseFirestore.instance
          .collection('groups')
          .doc(widget.groupId)
          .collection('goals')
          .doc(_todayDate)
          .get();
          
      if (goalDoc.exists && goalDoc.data() != null) {
        final data = goalDoc.data()!;
        final int minutes = data['goalMinutes'] ?? 0;
        _dailyGoalMinutesNotifier.value = minutes;
        _goalMinutesController.text = minutes.toString();
      }
    } catch (e) {
      print('목표 시간 로드 중 오류 발생: $e');
    }
  }
  
  // 오늘 목표 시간 저장
  Future<void> _saveDailyGoal(int minutes) async {
    if (_user == null) return;
    
    try {
      await FirebaseFirestore.instance
          .collection('groups')
          .doc(widget.groupId)
          .collection('goals')
          .doc(_todayDate)
          .set({
        'goalMinutes': minutes,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': _user!.uid,
        'updatedByEmail': _user!.email,
      }, SetOptions(merge: true));
      
      _dailyGoalMinutesNotifier.value = minutes;
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('오늘의 목표 시간이 설정되었습니다.')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('목표 시간 저장 중 오류가 발생했습니다: $e')),
      );
    }
  }
  
  // 오늘의 회고 로드
  Future<void> _loadTodayReflection() async {
    if (_user == null) return;
    
    try {
      final reflectionDoc = await FirebaseFirestore.instance
          .collection('groups')
          .doc(widget.groupId)
          .collection('reflections')
          .doc('${_user!.uid}_${_todayDate}')
          .get();
          
      if (reflectionDoc.exists && reflectionDoc.data() != null) {
        final data = reflectionDoc.data()!;
        final String reflection = data['reflection'] ?? '';
        final int rating = data['rating'] ?? 0;
        
        setState(() {
          _reflectionController.text = reflection;
          _reflectionRating = rating;
        });
      }
    } catch (e) {
      print('회고 로드 중 오류 발생: $e');
    }
  }
  
  // 오늘의 회고 저장
  Future<void> _saveTodayReflection(String reflection) async {
    if (_user == null) return;
    
    try {
      await FirebaseFirestore.instance
          .collection('groups')
          .doc(widget.groupId)
          .collection('reflections')
          .doc('${_user!.uid}_${_todayDate}')
          .set({
        'reflection': reflection,
        'date': _todayDate,
        'rating': _reflectionRating, // 별점 저장
        'userId': _user!.uid,
        'userEmail': _user!.email,
        'userName': _user!.displayName ?? _user!.email?.split('@')[0] ?? 'Unknown',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('오늘의 회고가 저장되었습니다.')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('회고 저장 중 오류가 발생했습니다: $e')),
      );
    }
  }
  
  // 오늘 기록된 시간 로드
  Future<void> _loadTodayTime() async {
    if (_user == null) return;
    
    try {
      final querySnapshot = await FirebaseFirestore.instance
          .collection('groups')
          .doc(widget.groupId)
          .collection('records')
          .where('date', isEqualTo: _todayDate)
          .get();
          
      int totalSeconds = 0;
      for (var doc in querySnapshot.docs) {
        Map<String, dynamic> data = doc.data();
        final int seconds = (data['time'] ?? 0).round();
        totalSeconds += seconds;
      }
      
      _todayTotalTimeNotifier.value = totalSeconds;
    } catch (e) {
      print('오늘 기록 시간 로드 중 오류 발생: $e');
    }
  }
  
  // 회고 패널 토글 함수
  void _toggleReflectionPanel() {
    // 항상 표시되므로 토글 기능 제거
    // setState(() {
    //   _showReflectionPanel = !_showReflectionPanel;
    // });
  }
  
  // 과거 회고 보기
  Future<void> _showPastReflections() async {
    if (_user == null) return;
    
    try {
      // 필터 초기화
      setState(() {
        _currentReflectionFilter = 'all';
        _teamMemberFilter = null;
      });
      
      await _showFilteredReflections();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('회고 기록을 불러오는 중 오류가 발생했습니다: $e')),
      );
    }
  }
  
  // 별점 표시 위젯 생성 함수
  Widget _buildRatingBar(double rating, bool readOnly) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        return IconButton(
          icon: Icon(
            index < rating.round() ? Icons.star : Icons.star_border,
            color: Colors.amber,
            size: readOnly ? 16 : 24,
          ),
          padding: EdgeInsets.zero,
          constraints: BoxConstraints(),
          onPressed: readOnly ? null : () {
            setState(() {
              _reflectionRating = index + 1;
            });
          },
        );
      }),
    );
  }
  
  // 필터링된 회고 표시 함수
  Future<void> _showFilteredReflections() async {
    if (_user == null) return;
    
    try {
      // 기본 쿼리 설정
      Query query = FirebaseFirestore.instance
          .collection('groups')
          .doc(widget.groupId)
          .collection('reflections')
          .orderBy('date', descending: true);
      
      // 날짜 필터 적용
      final now = DateTime.now();
      DateTime? filterDate;
      
      if (_currentReflectionFilter == 'last7') {
        filterDate = now.subtract(Duration(days: 7));
      } else if (_currentReflectionFilter == 'last30') {
        filterDate = now.subtract(Duration(days: 30));
      }
      
      // 팀원 필터는 클라이언트 측에서 처리하므로 Firebase 쿼리에서는 제외
      
      // 데이터 가져오기
      final reflectionsSnapshot = await query.get();
      
      if (reflectionsSnapshot.docs.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('저장된 회고가 없습니다.')),
        );
        return;
      }
      
      // 클라이언트 측에서 필터링 적용
      List<DocumentSnapshot> filteredDocs = reflectionsSnapshot.docs.where((doc) {
        final data = doc.data() as Map<String, dynamic>;
        
        // 날짜 필터 적용
        if (filterDate != null) {
          final docDate = data['date'] as String?;
          if (docDate == null) return false;
          
          try {
            final date = DateFormat('yyyy-MM-dd').parse(docDate);
            if (date.isBefore(filterDate)) return false;
          } catch (e) {
            print('날짜 파싱 오류: $e');
            return false;
          }
        }
        
        // 팀원 필터 적용
        if (_teamMemberFilter != null) {
          final userId = data['userId'] as String?;
          if (userId != _teamMemberFilter) return false;
        }
        
        return true;
      }).toList();
      
      if (filteredDocs.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('선택한 필터에 해당하는 회고가 없습니다.')),
        );
        return;
      }
      
      // 별점 평균 계산
      double totalRating = 0;
      int ratingCount = 0;
      
      for (var doc in filteredDocs) {
        final data = doc.data() as Map<String, dynamic>;
        final rating = data['rating'] ?? 0;
        if (rating > 0) {
          totalRating += rating;
          ratingCount++;
        }
      }
      
      final avgRating = ratingCount > 0 ? totalRating / ratingCount : 0;
      
      // 팀원 목록 가져오기
      final groupDoc = await FirebaseFirestore.instance
          .collection('groups')
          .doc(widget.groupId)
          .get();
          
      final groupData = groupDoc.data() as Map<String, dynamic>?;
      final memberIds = groupData?['members'] as List<dynamic>? ?? [];
      
      // 팀원 정보 가져오기
      List<Map<String, dynamic>> teamMembers = [];
      for (var memberId in memberIds) {
        try {
          final userDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(memberId)
              .get();
              
          if (userDoc.exists) {
            final userData = userDoc.data() as Map<String, dynamic>?;
            if (userData != null) {
              teamMembers.add({
                'id': memberId,
                'email': userData['email'] ?? '알 수 없음',
                'name': userData['displayName'] ?? userData['email']?.split('@')[0] ?? '알 수 없음',
              });
            }
          }
        } catch (e) {
          print('팀원 정보 가져오기 오류: $e');
        }
      }
      
      // 다이얼로그 표시
      showDialog(
        context: context,
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setState) {
              return AlertDialog(
                title: Text('지난 회고'),
                content: Container(
                  width: double.maxFinite,
                  height: 500,
                  child: Column(
                    children: [
                      // 필터 옵션
                      Container(
                        padding: EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('필터:', style: TextStyle(fontWeight: FontWeight.bold)),
                            Row(
                              children: [
                                _buildFilterChip('전체', 'all', setState),
                                SizedBox(width: 4),
                                _buildFilterChip('최근 7일', 'last7', setState),
                                SizedBox(width: 4),
                                _buildFilterChip('최근 30일', 'last30', setState),
                                SizedBox(width: 4),
                                TextButton.icon(
                                  icon: Icon(Icons.copy, size: 18),
                                  label: Text('복사'),
                                  onPressed: () {
                                    _copyReflections(filteredDocs);
                                  },
                                ),
                              ],
                            ),
                            
                            Padding(
                              padding: const EdgeInsets.only(top: 8.0),
                              child: DropdownButton<String?>(
                                hint: Text('팀원 선택'),
                                value: _teamMemberFilter,
                                isExpanded: true,
                                items: [
                                  DropdownMenuItem<String?>(
                                    value: null,
                                    child: Text('모든 팀원'),
                                  ),
                                  ...teamMembers.map((member) => 
                                    DropdownMenuItem<String?>(
                                      value: member['id'],
                                      child: Text(member['name']),
                                    )
                                  ).toList(),
                                ],
                                onChanged: (value) {
                                  setState(() {
                                    _teamMemberFilter = value;
                                  });
                                  // 필터 변경 시 데이터 다시 로드
                                  _showFilteredReflections();
                                  Navigator.pop(context);
                                },
                              ),
                            ),
                            
                            // 평균 별점 표시
                            Padding(
                              padding: const EdgeInsets.only(top: 8.0),
                              child: Row(
                                children: [
                                  Text('평균 별점: ', style: TextStyle(fontWeight: FontWeight.bold)),
                                  Text('${avgRating.toStringAsFixed(1)}'),
                                  SizedBox(width: 8),
                                  _buildRatingBar(avgRating.toDouble(), true),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      
                      SizedBox(height: 8),
                      
                      // 회고 목록
                      Expanded(
                        child: ListView.builder(
                          itemCount: filteredDocs.length,
                          itemBuilder: (context, index) {
                            final doc = filteredDocs[index];
                            final data = doc.data() as Map<String, dynamic>;
                            final date = data['date'] ?? '날짜 없음';
                            final reflection = data['reflection'] ?? '';
                            final rating = data['rating'] ?? 0;
                            final userEmail = data['userEmail'] ?? '작성자 알 수 없음';
                            
                            return Card(
                              margin: EdgeInsets.symmetric(vertical: 8.0),
                              child: Padding(
                                padding: EdgeInsets.all(12.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              date,
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 16,
                                              ),
                                            ),
                                            Text(
                                              userEmail,
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey,
                                              ),
                                            ),
                                          ],
                                        ),
                                        _buildRatingBar(rating.toDouble(), true),
                                      ],
                                    ),
                                    Divider(),
                                    Text(reflection),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('닫기'),
                  ),
                ],
              );
            },
          );
        },
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('회고 기록을 불러오는 중 오류가 발생했습니다: $e')),
      );
    }
  }
  
  // 필터 칩 위젯 생성 함수
  Widget _buildFilterChip(String label, String value, StateSetter setState) {
    return ChoiceChip(
      label: Text(label),
      selected: _currentReflectionFilter == value,
      onSelected: (selected) {
        if (selected) {
          setState(() {
            _currentReflectionFilter = value;
          });
          // 필터 변경 시 데이터 다시 로드
          _showFilteredReflections();
          Navigator.pop(context);
        }
      },
    );
  }
  
  // 회고 복사 기능 구현
  void _copyReflections(List<DocumentSnapshot> docs) {
    if (docs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('복사할 회고가 없습니다.')),
      );
      return;
    }
    
    // 복사할 텍스트 구성
    StringBuffer buffer = StringBuffer();
    buffer.writeln('===== ${widget.groupName} 팀 회고 =====');
    buffer.writeln('복사 시각: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}');
    buffer.writeln('총 ${docs.length}개의 회고');
    buffer.writeln('==============================\n');
    
    // 회고 데이터 정렬 (날짜 내림차순)
    docs.sort((a, b) {
      final aData = a.data() as Map<String, dynamic>;
      final bData = b.data() as Map<String, dynamic>;
      final aDate = aData['date'] as String? ?? '';
      final bDate = bData['date'] as String? ?? '';
      return bDate.compareTo(aDate); // 최신 날짜가 위로
    });
    
    // 날짜별로 그룹화
    Map<String, List<DocumentSnapshot>> groupedByDate = {};
    for (var doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      final date = data['date'] as String? ?? '날짜 없음';
      if (!groupedByDate.containsKey(date)) {
        groupedByDate[date] = [];
      }
      groupedByDate[date]!.add(doc);
    }
    
    // 날짜별로 정렬된 키 목록 생성
    List<String> sortedDates = groupedByDate.keys.toList()
      ..sort((a, b) => b.compareTo(a)); // 최신 날짜가 위로
    
    // 날짜별로 회고 추가
    for (var date in sortedDates) {
      buffer.writeln('\n[${date}]');
      
      for (var doc in groupedByDate[date]!) {
        final data = doc.data() as Map<String, dynamic>;
        final userEmail = data['userEmail'] as String? ?? '작성자 알 수 없음';
        final reflection = data['reflection'] as String? ?? '';
        final rating = data['rating'] as int? ?? 0;
        
        // 별점을 별 문자로 표시
        String stars = '';
        for (int i = 0; i < 5; i++) {
          stars += i < rating ? '★' : '☆';
        }
        
        buffer.writeln('\n- 작성자: $userEmail');
        buffer.writeln('- 별점: $stars ($rating/5)');
        buffer.writeln('- 내용: $reflection');
        buffer.writeln('------------------------------');
      }
    }
    
    // 클립보드에 복사
    Clipboard.setData(ClipboardData(text: buffer.toString())).then((_) {
      // 복사 완료 메시지
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${docs.length}개의 회고가 클립보드에 복사되었습니다.')),
      );
    });
  }
  
  // 과거 목표 및 달성률 기록 보기
  Future<void> _showPastGoals() async {
    if (_user == null) return;
    
    try {
      final goalsSnapshot = await FirebaseFirestore.instance
          .collection('groups')
          .doc(widget.groupId)
          .collection('goals')
          .orderBy('updatedAt', descending: true)
          .limit(30)  // 최근 30일 목표
          .get();
      
      if (goalsSnapshot.docs.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('저장된 목표가 없습니다.')),
        );
        return;
      }
      
      // 목표 날짜별로 실제 기록 시간 조회
      List<Map<String, dynamic>> goalRecords = [];
      
      for (var doc in goalsSnapshot.docs) {
        final data = doc.data();
        final date = doc.id;
        final goalMinutes = data['goalMinutes'] ?? 0;
        
        // 해당 날짜의 실제 기록 시간 조회
        final recordsSnapshot = await FirebaseFirestore.instance
            .collection('groups')
            .doc(widget.groupId)
            .collection('records')
            .where('date', isEqualTo: date)
            .get();
            
        int actualSeconds = 0;
        for (var recordDoc in recordsSnapshot.docs) {
          actualSeconds += ((recordDoc.data()['time'] ?? 0).round() as int);
        }
        
        int actualMinutes = actualSeconds ~/ 60;
        double progressPercentage = goalMinutes > 0 
            ? (actualMinutes / goalMinutes * 100).clamp(0, 100) 
            : 0;
            
        goalRecords.add({
          'date': date,
          'goalMinutes': goalMinutes,
          'actualMinutes': actualMinutes,
          'progressPercentage': progressPercentage,
          'updatedByEmail': data['updatedByEmail'] ?? '알 수 없음',
        });
      }
      
      showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: Text('지난 목표 및 달성률'),
            content: Container(
              width: double.maxFinite,
              height: 400,
              child: ListView.builder(
                itemCount: goalRecords.length,
                itemBuilder: (context, index) {
                  final record = goalRecords[index];
                  
                  return Card(
                    margin: EdgeInsets.symmetric(vertical: 8.0),
                    child: Padding(
                      padding: EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                record['date'],
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              Text(
                                record['updatedByEmail'],
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 8),
                          Text('목표: ${record['goalMinutes']}분'),
                          Text('실제: ${record['actualMinutes']}분'),
                          SizedBox(height: 8),
                          LinearProgressIndicator(
                            value: record['progressPercentage'] / 100,
                            backgroundColor: Colors.grey.shade200,
                            color: _getProgressColor(record['progressPercentage']),
                          ),
                          Text(
                            '달성률: ${record['progressPercentage'].toStringAsFixed(1)}%',
                            textAlign: TextAlign.end,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('닫기'),
              ),
            ],
          );
        },
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('목표 기록을 불러오는 중 오류가 발생했습니다: $e')),
      );
    }
  }
  
  // 진행률에 따른 색상 반환
  Color _getProgressColor(double percentage) {
    if (percentage >= 100) return Colors.green;
    if (percentage >= 75) return Colors.lightGreen;
    if (percentage >= 50) return Colors.amber;
    if (percentage >= 25) return Colors.orange;
    return Colors.red;
  }
  
  // 목표 시간 설정 다이얼로그 표시
  void _showGoalSettingDialog() {
    _goalMinutesController.text = _dailyGoalMinutesNotifier.value.toString();
    
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('오늘의 목표 시간 설정'),
          content: TextField(
            controller: _goalMinutesController,
            focusNode: _goalMinutesFocusNode,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: '목표 시간 (분)',
              hintText: '예: 60 (1시간)',
            ),
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('취소'),
            ),
            TextButton(
              onPressed: () {
                final minutes = int.tryParse(_goalMinutesController.text) ?? 0;
                _saveDailyGoal(minutes);
                Navigator.pop(context);
              },
              child: Text('저장'),
            ),
          ],
        );
      },
    );
  }
}

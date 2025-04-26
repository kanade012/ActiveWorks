import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:planner/page/create_group_page.dart';
import 'package:planner/page/join_group_page.dart';
import 'package:planner/page/group_list_page.dart';
import 'package:window_manager/window_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import '../services/auth_service.dart';
import '../models/user_model.dart';
import 'group_detail_page.dart';

class MainPage extends StatefulWidget {
  const MainPage({Key? key}) : super(key: key);

  @override
  State<MainPage> createState() => _MainPageState();
}

enum SortOption {
  latest, // 최신순
  oldest, // 오래된순
  time, // 기록 시간순
  date, // 날짜별
}

class _MainPageState extends State<MainPage> with WidgetsBindingObserver {
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
  
  // 회고 표시 여부
  bool _showReflectionPanel = false;
  
  // 키보드 포커스 노드 추가
  final FocusNode _keyboardFocusNode = FocusNode();
  final FocusNode _referenceFocusNode = FocusNode();
  final FocusNode _meetingDataFocusNode = FocusNode();
  final FocusNode _reflectionFocusNode = FocusNode();
  final FocusNode _goalMinutesFocusNode = FocusNode();

  // 전역 포커스 변경 감지 구독
  late final StreamSubscription<bool> _focusSubscription;

  // 텍스트 필드 포커스 상태 추적
  bool _isTextFieldFocused = false;

  // 대신 AuthService 사용
  final AuthService _authService = AuthService();

  UserModel? get _user => _authService.currentUser;

  // 화면 크기와 고정 상태를 관리하기 위한 변수 추가
  bool _isExpanded = true;
  bool _isAlwaysOnTop = false; // 기본값을 false로 변경

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
      bool savedState = prefs.getBool('is_always_on_top') ?? false;

      // 현재 상태와 다를 때만 업데이트
      if (_isAlwaysOnTop != savedState) {
        setState(() {
          _isAlwaysOnTop = savedState;
        });

        await windowManager.setAlwaysOnTop(savedState);
      }
    } catch (e) {
      print('화면 고정 상태 불러오기 중 오류 발생: $e');
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
        _isExpanded = true; // 기본값은 확장된 상태
      });

      // 현재 창 크기 가져오기 (기본값 사용)
      Size currentSize = Size(800, 600);

      WindowOptions windowOptions = WindowOptions(
        size: _isExpanded
            ? Size(currentSize.width, 600)
            : Size(currentSize.width, 50),
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
    // Firebase는 main.dart에서 이미 초기화되었으므로 여기서는 호출하지 않습니다.
    _initializeWindow(); // 창 초기화 함수 호출
    _loadAlwaysOnTopState(); // 저장된 화면 고정 상태 불러오기
    _loadTotalTime(); // 총 기록 시간 로드
    _loadTodayTime(); // 오늘의 기록 시간 로드
    _loadDailyGoal(); // 목표 시간 로드
    _loadTodayReflection(); // 오늘의 회고 로드
    
    // 로그인된 사용자가 있는 경우 첫 번째 그룹 자동 열기
    _checkAndOpenFirstGroup();

    // 위젯 바인딩 옵저버 등록
    WidgetsBinding.instance.addObserver(this);

    // 포커스 노드 설정 및 감시
    _setupFocusNodes();

    // 전체 키보드 포커스 설정
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FocusScope.of(context).requestFocus(_keyboardFocusNode);
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

      await FirebaseFirestore.instance
          .collection('users')
          .doc(_user!.uid)
          .collection('records')
          .add({
        'reference': _reference,
        'meetingData': _meetingData,
        'time': currentTime,
        'timestamp': FieldValue.serverTimestamp(),
        'date': today,
        'timeOfDay':
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
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
      // 삭제할 문서의 시간 정보 가져오기
      final docSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(_user!.uid)
          .collection('records')
          .doc(docId)
          .get();

      if (docSnapshot.exists) {
        final data = docSnapshot.data() as Map<String, dynamic>;
        final int timeToSubtract = (data['time'] ?? 0).round();
        final String recordDate = data['date'] ?? '';

        // 문서 삭제
        await FirebaseFirestore.instance
            .collection('users')
            .doc(_user!.uid)
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
      {String? date, String? timeOfDay}) {
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

  void _logout() async {
    await _authService.signOut();
    // 로그아웃 후 로그인 페이지로 이동
    Navigator.of(context).pushReplacementNamed('/login');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // 앱 상태 변경 시 포커스 확인
    if (state == AppLifecycleState.resumed) {
      _checkFocusState();
      _loadAlwaysOnTopState(); // 앱이 재개될 때 화면 고정 상태 다시 로드
    }
  }

  // 페이지가 다시 보일 때 화면 고정 상태 확인
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadAlwaysOnTopState(); // 페이지가 다시 활성화될 때 화면 고정 상태 다시 로드
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
  void dispose() {
    _timer?.cancel();
    _elapsedSecondsNotifier.dispose();
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
    if (_user == null) {
      return FirebaseFirestore.instance.collection('dummy');
    }

    Query<Map<String, dynamic>> query = FirebaseFirestore.instance
        .collection('users')
        .doc(_user!.uid)
        .collection('records');

    // 모든 정렬 옵션을 timestamp로 처리하고 클라이언트에서 추가 정렬
    return query.orderBy('timestamp', descending: _currentSortOption != SortOption.oldest);
  }

  // 정렬 옵션 변경 함수
  void _changeSortOption(SortOption option) {
    setState(() {
      _currentSortOption = option;
      // 정렬 옵션이 변경되면 화면을 다시 그립니다.
      // FutureBuilder를 사용하므로 build 메소드가 다시 호출되어 쿼리가 실행됩니다.
    });
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
        !_meetingDataFocusNode.hasFocus &&
        !_reflectionFocusNode.hasFocus &&
        !_goalMinutesFocusNode.hasFocus) {
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

  // 총 기록 시간을 로드하는 함수
  Future<void> _loadTotalTime() async {
    if (_user == null) return;

    try {
      final querySnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(_user!.uid)
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

  // 사용자가 로그인한 경우 첫 번째 그룹을 자동으로 열기
  Future<void> _checkAndOpenFirstGroup() async {
    // 로그인된 사용자가 있는지 확인
    if (_user == null) {
      print('자동 그룹 열기: 로그인된 사용자가 없습니다.');
      return;
    }
    
    try {
      print('자동 그룹 열기: 사용자 ${_user!.email}의 그룹 확인 중...');
      // 사용자의 그룹 목록 가져오기
      final groupsSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(_user!.uid)
          .collection('groups')
          .orderBy('joinedAt', descending: true)
          .limit(1)
          .get();
      
      print('자동 그룹 열기: 그룹 데이터 개수: ${groupsSnapshot.docs.length}');
      
      // 그룹이 있는 경우 첫 번째 그룹 열기
      if (groupsSnapshot.docs.isNotEmpty) {
        final firstGroup = groupsSnapshot.docs.first;
        final groupData = firstGroup.data();
        
        print('자동 그룹 열기: 첫 번째 그룹 이름: ${groupData['name'] ?? '(이름 없음)'}, ID: ${groupData['groupId']}');
        
        // 약간의 지연을 주어 UI가 완전히 로드된 후 이동
        Future.delayed(Duration(milliseconds: 500), () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => GroupDetailPage(
                groupId: groupData['groupId'],
                groupName: groupData['name'] ?? '(이름 없음)',
              ),
            ),
          );
        });
      } else {
        print('자동 그룹 열기: 사용자가 속한 그룹이 없습니다.');
      }
    } catch (e) {
      print('첫 번째 그룹 자동 열기 중 오류 발생: $e');
      // 오류가 발생해도 앱은 계속 실행
    }
  }

  // 오늘의 목표 시간 로드
  Future<void> _loadDailyGoal() async {
    if (_user == null) return;
    
    try {
      final goalDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(_user!.uid)
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
          .collection('users')
          .doc(_user!.uid)
          .collection('goals')
          .doc(_todayDate)
          .set({
        'goalMinutes': minutes,
        'updatedAt': FieldValue.serverTimestamp(),
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
          .collection('users')
          .doc(_user!.uid)
          .collection('reflections')
          .doc(_todayDate)
          .get();
          
      if (reflectionDoc.exists && reflectionDoc.data() != null) {
        final data = reflectionDoc.data()!;
        final String reflection = data['reflection'] ?? '';
        _reflectionController.text = reflection;
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
          .collection('users')
          .doc(_user!.uid)
          .collection('reflections')
          .doc(_todayDate)
          .set({
        'reflection': reflection,
        'date': _todayDate,
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
          .collection('users')
          .doc(_user!.uid)
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
    setState(() {
      _showReflectionPanel = !_showReflectionPanel;
    });
  }
  
  // 과거 회고 보기
  Future<void> _showPastReflections() async {
    if (_user == null) return;
    
    try {
      final reflectionsSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(_user!.uid)
          .collection('reflections')
          .orderBy('date', descending: true)
          .limit(30)  // 최근 30일 회고
          .get();
      
      if (reflectionsSnapshot.docs.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('저장된 회고가 없습니다.')),
        );
        return;
      }
      
      showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: Text('지난 회고'),
            content: Container(
              width: double.maxFinite,
              height: 400,
              child: ListView.builder(
                itemCount: reflectionsSnapshot.docs.length,
                itemBuilder: (context, index) {
                  final doc = reflectionsSnapshot.docs[index];
                  final data = doc.data();
                  final date = data['date'] ?? '날짜 없음';
                  final reflection = data['reflection'] ?? '';
                  
                  return Card(
                    margin: EdgeInsets.symmetric(vertical: 8.0),
                    child: Padding(
                      padding: EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            date,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
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
        SnackBar(content: Text('회고 기록을 불러오는 중 오류가 발생했습니다: $e')),
      );
    }
  }
  
  // 과거 목표 및 달성률 기록 보기
  Future<void> _showPastGoals() async {
    if (_user == null) return;
    
    try {
      final goalsSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(_user!.uid)
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
            .collection('users')
            .doc(_user!.uid)
            .collection('records')
            .where('date', isEqualTo: date)
            .get();
            
        int actualSeconds = 0;
        for (var recordDoc in recordsSnapshot.docs) {
          final num timeValue = recordDoc.data()['time'] ?? 0;
          actualSeconds += timeValue.round();
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
                          Text(
                            record['date'],
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
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

  @override
  Widget build(BuildContext context) {
    // 페이지가 화면에 보일 때마다 화면 고정 상태 확인
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadAlwaysOnTopState();
    });

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
          appBar: isSmallScreen
              ? null
              : PreferredSize(
            preferredSize: Size.fromHeight(70),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                AppBar(
                  backgroundColor: Color(0xFFF9FAFC),
                  // 배경색 검정
                  title: Text('My workspace'),
                  // 스크롤 할 때 앱바 색이 변경되지 않도록 설정
                  scrolledUnderElevation: 0,
                  // 스크롤 시 높이 효과 제거
                  shadowColor: Colors.transparent,
                  // 그림자 색상 투명하게
                  elevation: 0,
                  // 앱바 높이 효과 제거
                  forceMaterialTransparency: false,
                  // 머티리얼 효과 제거

                  actions: [
                    // 정렬 버튼을 드롭다운으로 변경
                    PopupMenuButton<SortOption>(
                      color: Colors.white,
                      icon: Row(
                        children: [
                          Text(
                              '정렬 : ${_getSortOptionText(_currentSortOption)}',
                              style: TextStyle(
                                  fontSize: 14, color: Colors.black)),
                          Icon(Icons.arrow_drop_down,
                              color: Colors.black),
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
                          value: SortOption.date,
                          child: Text('날짜별',
                              style: TextStyle(color: Colors.black)),
                        ),
                      ],
                    ),
                    // 햄버거 메뉴를 PopupMenuButton으로 변경
                    PopupMenuButton<String>(
                      color: Colors.white,
                      icon: Icon(Icons.menu, color: Colors.black),
                      onSelected: (String value) {
                        switch (value) {
                          case 'logout':
                            _logout();
                            break;
                          case 'create_group':
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => CreateGroupPage(),
                              ),
                            );
                            break;
                          case 'join_group':
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => JoinGroupPage(),
                              ),
                            );
                            break;
                          case 'view_groups':
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => GroupListPage(),
                              ),
                            );
                            break;
                        }
                      },
                      itemBuilder: (BuildContext context) =>
                      <PopupMenuEntry<String>>[
                        PopupMenuItem<String>(
                          value: 'logout',
                          child: Row(
                            children: [
                              Icon(Icons.logout, color: Colors.black),
                              SizedBox(width: 8),
                              Text('로그아웃',
                                  style: TextStyle(color: Colors.black)),
                            ],
                          ),
                        ),
                        PopupMenuItem<String>(
                          value: 'create_group',
                          child: Row(
                            children: [
                              Icon(Icons.group_add, color: Colors.black),
                              SizedBox(width: 8),
                              Text('그룹생성',
                                  style: TextStyle(color: Colors.black)),
                            ],
                          ),
                        ),
                        PopupMenuItem<String>(
                          value: 'join_group',
                          child: Row(
                            children: [
                              Icon(Icons.person_add, color: Colors.black),
                              SizedBox(width: 8),
                              Text('그룹참가',
                                  style: TextStyle(color: Colors.black)),
                            ],
                          ),
                        ),
                        PopupMenuItem<String>(
                          value: 'view_groups',
                          child: Row(
                            children: [
                              Icon(Icons.groups, color: Colors.black),
                              SizedBox(width: 8),
                              Text('그룹보기',
                                  style: TextStyle(color: Colors.black)),
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
          // 작은 화면에서는 배경 투명하게 설정
          backgroundColor:
          isSmallScreen ? Colors.transparent : Color(0xFFF9FAFC),
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
                        Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              IconButton(
                                icon: Icon(Icons.edit, size: 20),
                                tooltip: '목표 설정',
                                onPressed: _showGoalSettingDialog,
                              ),
                              IconButton(
                                icon: Icon(Icons.history, size: 20),
                                tooltip: '지난 목표 보기',
                                onPressed: _showPastGoals,
                              ),
                              IconButton(
                                icon: Icon(Icons.note_alt_outlined, size: 20),
                                tooltip: '회고 토글',
                                onPressed: _toggleReflectionPanel,
                              ),
                            ],
                          ),
                        ),
                        
                        // 목표 시간 및 진행률 표시
                        Container(
                          padding: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                          child: ValueListenableBuilder(
                            valueListenable: _dailyGoalMinutesNotifier,
                            builder: (context, goalMinutes, _) {
                              return ValueListenableBuilder(
                                valueListenable: _todayTotalTimeNotifier,
                                builder: (context, todaySeconds, _) {
                                  final todayMinutes = todaySeconds ~/ 60;
                                  final progress = goalMinutes > 0 
                                      ? (todayMinutes / goalMinutes * 100).clamp(0.0, 100.0) 
                                      : 0.0;
                                  
                                  return Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '오늘의 목표',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),
                                      SizedBox(height: 4),
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
                                  );
                                },
                              );
                            },
                          ),
                        ),
                        
                        // 회고 패널 (토글 가능)
                        if (_showReflectionPanel)
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
                          
                        SizedBox(height: 8),
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(15)),
                            child: FutureBuilder<QuerySnapshot>(
                              future: _getSortedQuery().get(),
                              builder: (context, snapshot) {
                                if (snapshot.hasError) {
                                  return Center(
                                      child: Text('데이터를 불러오는 중 오류가 발생했습니다.'));
                                }
                                if (snapshot.connectionState ==
                                    ConnectionState.waiting) {
                                  return Center(child: CircularProgressIndicator());
                                }
                                if (snapshot.data == null ||
                                    snapshot.data!.docs.isEmpty) {
                                  return Center(child: Text('저장된 데이터가 없습니다.'));
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
                                          ...docs.map((doc) {
                                            Map<String, dynamic> data = doc
                                                .data() as Map<String, dynamic>;
                                            return InkWell(
                                              highlightColor:
                                              Colors.transparent,
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
                                                title: Text(
                                                    data['reference'] ?? ''),
                                                subtitle: Column(
                                                  crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                                  children: [
                                                    Text(data['meetingData'] ??
                                                        ''),
                                                    Text(
                                                        '날짜: ${data['date'] ?? ''} ${data['timeOfDay'] ?? ''}'),
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
                                      Map<String, dynamic> data = document
                                          .data() as Map<String, dynamic>;
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
                                            crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                            children: [
                                              Text(data['meetingData'] ?? ''),
                                              Text(
                                                  '날짜: ${data['date'] ?? ''} ${data['timeOfDay'] ?? ''}'),
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
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 10),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Padding(
                                  padding:
                                  EdgeInsets.symmetric(horizontal: 30)),
                              // 제목과 부제목 입력 필드 유지
                              Expanded(
                                child: TextField(
                                  focusNode: _referenceFocusNode,
                                  // 포커스 노드 할당
                                  controller: _referenceController,
                                  decoration: InputDecoration(
                                      hintText: "제목", border: InputBorder.none),
                                  onChanged: (value) => _reference = value,
                                  onSubmitted: (_) => _unfocusTextFields(),
                                ),
                              ),
                              Expanded(
                                child: TextField(
                                  focusNode: _meetingDataFocusNode,
                                  // 포커스 노드 할당
                                  controller: _meetingDataController,
                                  decoration: InputDecoration(
                                      hintText: "부제목",
                                      border: InputBorder.none),
                                  onChanged: (value) => _meetingData = value,
                                  onSubmitted: (_) => _unfocusTextFields(),
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

                              // 타이머 제어 버튼들
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // 화면 확장/축소 버튼
                                  IconButton(
                                    icon: Icon(
                                      _isExpanded
                                          ? Icons.expand_more
                                          : Icons.expand_less,
                                      color: Colors.blue,
                                    ),
                                    onPressed: _toggleExpand,
                                  ),

                                  // 화면 고정 버튼
                                  IconButton(
                                    icon: Icon(
                                      _isAlwaysOnTop
                                          ? Icons.push_pin
                                          : Icons.push_pin_outlined,
                                      color: _isAlwaysOnTop
                                          ? Colors.orange
                                          : Colors.grey,
                                    ),
                                    onPressed: _toggleAlwaysOnTop,
                                  ),

                                  // 재생/일시정지 버튼
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

                                  // 완료 버튼 (정지 및 저장)
                                  IconButton(
                                    icon: Icon(Icons.stop, color: Colors.red),
                                    onPressed: (_isPlaying || _isPaused)
                                        ? _stopTimer
                                        : null,
                                  ),

                                  // 취소 버튼 (리셋)
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
                          boxShadow: isSmallScreen
                              ? null
                              : [
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

                              // 타이머 제어 버튼들
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // 화면 확장/축소 버튼
                                  IconButton(
                                    icon: Icon(
                                      _isExpanded
                                          ? Icons.expand_more
                                          : Icons.expand_less,
                                      color: Colors.blue,
                                    ),
                                    onPressed: _toggleExpand,
                                  ),

                                  // 화면 고정 버튼
                                  IconButton(
                                    icon: Icon(
                                      _isAlwaysOnTop
                                          ? Icons.push_pin
                                          : Icons.push_pin_outlined,
                                      color: _isAlwaysOnTop
                                          ? Colors.orange
                                          : Colors.grey,
                                    ),
                                    onPressed: _toggleAlwaysOnTop,
                                  ),

                                  // 재생/일시정지 버튼
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

                                  // 완료 버튼 (정지 및 저장)
                                  IconButton(
                                    icon: Icon(Icons.stop, color: Colors.red),
                                    onPressed: (_isPlaying || _isPaused)
                                        ? _stopTimer
                                        : null,
                                  ),

                                  // 취소 버튼 (리셋)
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
}

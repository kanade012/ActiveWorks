import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class JoinGroupPage extends StatefulWidget {
  const JoinGroupPage({Key? key}) : super(key: key);

  @override
  State<JoinGroupPage> createState() => _JoinGroupPageState();
}

class _JoinGroupPageState extends State<JoinGroupPage> {
  final _formKey = GlobalKey<FormState>();
  final _joinCodeController = TextEditingController();
  bool _isLoading = false;

  Future<void> _joinGroup() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('로그인이 필요합니다.')),
        );
        return;
      }

      final joinCode = _joinCodeController.text.toUpperCase();
      
      // 참가 코드로 그룹 찾기
      final groupSnapshot = await FirebaseFirestore.instance
          .collection('groups')
          .where('joinCode', isEqualTo: joinCode)
          .limit(1)
          .get();

      if (groupSnapshot.docs.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('유효하지 않은 참가 코드입니다.')),
        );
        return;
      }

      final groupDoc = groupSnapshot.docs.first;
      final groupId = groupDoc.id;
      final groupData = groupDoc.data();
      
      // 이미 참가한 그룹인지 확인
      final List<dynamic> members = groupData['members'] ?? [];
      if (members.contains(user.uid)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('이미 참가한 그룹입니다.')),
        );
        return;
      }

      // 그룹에 사용자 추가
      members.add(user.uid);
      await FirebaseFirestore.instance
          .collection('groups')
          .doc(groupId)
          .update({'members': members});

      // 사용자의 그룹 목록에도 추가
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('groups')
          .doc(groupId)
          .set({
        'groupId': groupId,
        'joinedAt': FieldValue.serverTimestamp(),
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('그룹에 참가했습니다.')),
      );
      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('그룹 참가에 실패했습니다: $e')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('그룹 참가'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _joinCodeController,
                decoration: InputDecoration(labelText: '참가 코드'),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return '참가 코드를 입력해주세요.';
                  }
                  return null;
                },
              ),
              SizedBox(height: 20),
              ElevatedButton(
                onPressed: _isLoading ? null : _joinGroup,
                child: _isLoading
                    ? CircularProgressIndicator()
                    : Text('그룹 참가하기'),
              ),
            ],
          ),
        ),
      ),
    );
  }
} 
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:math';

class CreateGroupPage extends StatefulWidget {
  const CreateGroupPage({Key? key}) : super(key: key);

  @override
  State<CreateGroupPage> createState() => _CreateGroupPageState();
}

class _CreateGroupPageState extends State<CreateGroupPage> {
  final _formKey = GlobalKey<FormState>();
  final _groupNameController = TextEditingController();
  bool _isLoading = false;

  String _generateJoinCode() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ1234567890';
    final random = Random();
    return String.fromCharCodes(
      Iterable.generate(
        6, // 6자리 코드
        (_) => chars.codeUnitAt(random.nextInt(chars.length)),
      ),
    );
  }

  Future<void> _createGroup() async {
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

      final joinCode = _generateJoinCode();
      final groupRef = FirebaseFirestore.instance.collection('groups').doc();

      await groupRef.set({
        'id': groupRef.id,
        'name': _groupNameController.text,
        'joinCode': joinCode,
        'members': [user.uid],
        'createdBy': user.uid,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // 사용자의 그룹 목록에도 추가
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('groups')
          .doc(groupRef.id)
          .set({
        'groupId': groupRef.id,
        'joinedAt': FieldValue.serverTimestamp(),
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('그룹이 생성되었습니다. 참가 코드: $joinCode')),
      );
      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('그룹 생성에 실패했습니다: $e')),
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
        title: Text('그룹 생성'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _groupNameController,
                decoration: InputDecoration(labelText: '그룹 이름'),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return '그룹 이름을 입력해주세요.';
                  }
                  return null;
                },
              ),
              SizedBox(height: 20),
              ElevatedButton(
                onPressed: _isLoading ? null : _createGroup,
                child: _isLoading
                    ? CircularProgressIndicator()
                    : Text('그룹 생성하기'),
              ),
            ],
          ),
        ),
      ),
    );
  }
} 
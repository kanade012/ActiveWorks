import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:planner/page/group_detail_page.dart';
import '../services/auth_service.dart';
import '../models/user_model.dart';

class GroupListPage extends StatefulWidget {
  const GroupListPage({Key? key}) : super(key: key);

  @override
  State<GroupListPage> createState() => _GroupListPageState();
}

class _GroupListPageState extends State<GroupListPage> {
  final AuthService _authService = AuthService();
  
  @override
  Widget build(BuildContext context) {
    final user = _authService.currentUser;
    
    return Scaffold(
      backgroundColor: Color(0xFFF9FAFC),
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(70),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            AppBar(
              backgroundColor: Color(0xFFF9FAFC),
              title: Text('내 그룹'),
              scrolledUnderElevation: 0,
              shadowColor: Colors.transparent,
              elevation: 0,
            ),
          ],
        ),
      ),
      body: user == null
          ? Center(child: Text('로그인이 필요합니다.'))
          : StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(user.uid)
                  .collection('groups')
                  .orderBy('joinedAt', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('데이터를 불러오는 중 오류가 발생했습니다.'));
                }

                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(child: CircularProgressIndicator());
                }

                final groups = snapshot.data?.docs ?? [];
                if (groups.isEmpty) {
                  return Center(child: Text('참여 중인 그룹이 없습니다.'));
                }

                return ListView.builder(
                  padding: EdgeInsets.all(16),
                  itemCount: groups.length,
                  itemBuilder: (context, index) {
                    final groupData = groups[index].data() as Map<String, dynamic>;
                    final isCreator = groupData['isCreator'] ?? false;
                    
                    return Card(
                      elevation: 2,
                      margin: EdgeInsets.only(bottom: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListTile(
                        contentPadding: EdgeInsets.all(16),
                        title: Text(
                          groupData['name'] ?? '(이름 없음)',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                        subtitle: isCreator
                            ? Text('내가 만든 그룹', style: TextStyle(color: Colors.blue))
                            : null,
                        trailing: Icon(Icons.arrow_forward_ios, size: 16),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => GroupDetailPage(
                                groupId: groupData['groupId'],
                                groupName: groupData['name'] ?? '(이름 없음)',
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
} 
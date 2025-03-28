import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:planner/page/group_detail_page.dart';

class GroupListPage extends StatefulWidget {
  const GroupListPage({Key? key}) : super(key: key);

  @override
  State<GroupListPage> createState() => _GroupListPageState();
}

class _GroupListPageState extends State<GroupListPage> {
  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        scrolledUnderElevation: 0, // 스크롤 시 높이 효과 제거
        shadowColor: Colors.transparent, // 그림자 색상 투명하게
        elevation: 0, // 앱바 높이 효과 제거
        forceMaterialTransparency: false, // 머티리얼 효과 제거
        title: Text('내 그룹 목록'),
      ),
      body: user == null
          ? Center(child: Text('로그인이 필요합니다.'))
          : StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(user.uid)
                  .collection('groups')
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('오류가 발생했습니다.'));
                }

                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(child: CircularProgressIndicator());
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Center(child: Text('참가한 그룹이 없습니다.'));
                }

                return ListView.builder(
                  padding: EdgeInsets.symmetric(horizontal: 20,),
                  itemCount: snapshot.data!.docs.length,
                  itemBuilder: (context, index) {
                    final groupDoc = snapshot.data!.docs[index];
                    final groupId = groupDoc['groupId'];

                    return FutureBuilder<DocumentSnapshot>(
                      future: FirebaseFirestore.instance
                          .collection('groups')
                          .doc(groupId)
                          .get(),
                      builder: (context, groupSnapshot) {
                        if (!groupSnapshot.hasData) {
                          return ListTile(
                            title: Text('로딩 중...'),
                          );
                        }

                        final groupData = groupSnapshot.data!.data() as Map<String, dynamic>;
                        final groupName = groupData['name'] ?? '이름 없는 그룹';

                        return Column(
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                border: Border.all(width: 0.4),
                                borderRadius: BorderRadius.circular(12),
                                color: Colors.white
                              ),
                              child: ListTile(
                                hoverColor: Colors.transparent,
                                splashColor: Colors.transparent,
                                title: Text(groupName),
                                trailing: Icon(Icons.arrow_forward_ios),
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => GroupDetailPage(
                                        groupId: groupId,
                                        groupName: groupName,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                            SizedBox(height: 10,)
                          ],
                        );
                      },
                    );
                  },
                );
              },
            ),
    );
  }
} 
import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 定数の定義
const String KEY_SENDER_NAME = "senderName";
const String KEY_SUBJECT = "subject";
const String KEY_BODY = "body";
const String KEY_RECIPIENT_LIST = "recipientList";

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '画像選択＆メール送信',
      theme: ThemeData(
        primarySwatch: Colors.orange,
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            minimumSize: Size(double.infinity, 60),
            textStyle: TextStyle(fontSize: 24),
          ),
        ),
      ),
      home: ImagePickerScreen(),
    );
  }
}

class ImagePickerScreen extends StatefulWidget {
  @override
  _ImagePickerScreenState createState() => _ImagePickerScreenState();
}

class _ImagePickerScreenState extends State<ImagePickerScreen> {
  final ImagePicker _picker = ImagePicker();
  List<File> _selectedImages = [];
  bool _isSending = false;
  final ValueNotifier<String> _progressMessageNotifier = ValueNotifier<String>("");
  // フラグで進捗ダイアログの表示状態を管理（多重展開を防止）
  bool _isDialogShowing = false;

  @override
  void dispose() {
    _progressMessageNotifier.dispose();
    super.dispose();
  }

  // 画像選択（複数画像対応）
  Future<void> _pickImages() async {
    final List<XFile>? pickedFiles = await _picker.pickMultiImage();
    if (pickedFiles != null) {
      setState(() {
        _selectedImages = pickedFiles.map((file) => File(file.path)).toList();
      });
    }
  }

  // 画像圧縮処理
  Future<File> _compressImage(File file) async {
    final tempDir = await getTemporaryDirectory();
    final targetPath = '${tempDir.path}/${DateTime.now().millisecondsSinceEpoch}.jpg';
    final result = await FlutterImageCompress.compressWithFile(
      file.absolute.path,
      quality: 50,
      format: CompressFormat.jpeg,
    );
    if (result == null) return file;
    return await File(targetPath).writeAsBytes(result);
  }

  // 送信先選択ダイアログの表示
  Future<List<Map<String, String>>?> _selectRecipients(List<Map<String, String>> allRecipients) async {
    List<bool> selected = List<bool>.filled(allRecipients.length, false);
    return await showDialog<List<Map<String, String>>>(
      context: context,
      barrierDismissible: true, // ダイアログ外タップで閉じる設定
      builder: (context) {
        return AlertDialog(
          title: Text("送信先を選択してください"),
          content: StatefulBuilder(
            builder: (context, setState) {
              return Container(
                width: double.maxFinite,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: allRecipients.length,
                  itemBuilder: (context, index) {
                    final recipient = allRecipients[index];
                    return CheckboxListTile(
                      title: Text(
                        "${recipient['label']}",
                        style: TextStyle(fontSize: 18),
                      ),
                      value: selected[index],
                      onChanged: (bool? value) {
                        setState(() {
                          selected[index] = value ?? false;
                        });
                      },
                    );
                  },
                ),
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context, null); // キャンセル時は null を返す
              },
              child: Text("キャンセル"),
            ),
            ElevatedButton(
              onPressed: () {
                List<Map<String, String>> chosen = [];
                for (int i = 0; i < allRecipients.length; i++) {
                  if (selected[i]) {
                    chosen.add(allRecipients[i]);
                  }
                }
                Navigator.pop(context, chosen);
              },
              child: Text("決定"),
            ),
          ],
        );
      },
    );
  }

  // 進捗ダイアログの表示
  void _showProgressDialog() {
    // 既にダイアログが表示されている場合は新たに表示しない
    if (_isDialogShowing) return;

    _isDialogShowing = true;
    showDialog(
      context: context,
      barrierDismissible: false, // ユーザーが外側をタップしても閉じない
      builder: (_) {
        return ValueListenableBuilder<String>(
          valueListenable: _progressMessageNotifier,
          builder: (context, value, child) {
            return Dialog(
              backgroundColor: Colors.white,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text(value, style: TextStyle(fontSize: 16)),
                  ],
                ),
              ),
            );
          },
        );
      },
    ).then((_) {
      // ダイアログが閉じられた後にフラグを更新
      _isDialogShowing = false;
    });
  }

  // 進捗ダイアログの非表示処理
  void _hideProgressDialog() {
    if (_isDialogShowing) {
      Navigator.of(context, rootNavigator: true).pop();
      _isDialogShowing = false;
    }
  }

  // メール送信処理（非同期で実行）
  Future<void> _sendEmail() async {
    if (_selectedImages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('画像が選択されていません')));
      return;
    }
    if (_isSending) return;
    setState(() {
      _isSending = true;
    });

    _progressMessageNotifier.value = "処理を開始します...";
    _showProgressDialog();

    try {
      // 画像の圧縮処理
      _progressMessageNotifier.value = "画像を圧縮中...";
      List<File> compressedFiles = [];
      for (File file in _selectedImages) {
        File compressed = await _compressImage(file);
        compressedFiles.add(compressed);
      }

      // ZIPファイルの作成
      _progressMessageNotifier.value = "ZIPファイルを作成中...";
      final archive = Archive();
      for (File file in compressedFiles) {
        List<int> fileBytes = await file.readAsBytes();
        String fileName = p.basename(file.path);
        archive.addFile(ArchiveFile(fileName, fileBytes.length, fileBytes));
      }
      List<int>? zipData = ZipEncoder().encode(archive);
      if (zipData == null) throw Exception("ZIPエンコードに失敗しました");
      final tempDir = await getTemporaryDirectory();
      final formattedDate = DateFormat('yyMMdd').format(DateTime.now());
      final zipPath = '${tempDir.path}/images_$formattedDate.zip';
      File zipFile = File(zipPath);
      await zipFile.writeAsBytes(zipData);

      // ZIPファイルサイズのチェック
      _progressMessageNotifier.value = "ZIPファイルサイズをチェック中...";
      int zipFileSize = await zipFile.length();
      const int maxAttachmentSize = 25 * 1024 * 1024;
      if (zipFileSize > maxAttachmentSize) {
        _hideProgressDialog(); // 既存の進捗ダイアログを閉じる
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('添付ファイルのサイズが25MBを超えています')));
        setState(() {
          _isSending = false;
        });
        return;
      }

      // 保存済みの送信先リストの取得
      final prefs = await SharedPreferences.getInstance();
      String? recipientListJson = prefs.getString(KEY_RECIPIENT_LIST);
      if (recipientListJson == null) {
        _hideProgressDialog(); // ダイアログを閉じる
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('送信先が設定されていません')));
        setState(() {
          _isSending = false;
        });
        return;
      }
      List<dynamic> jsonList = jsonDecode(recipientListJson);
      List<Map<String, String>> allRecipients = jsonList.map<Map<String, String>>((item) {
        return {
          'label': item['label'] as String,
          'email': item['email'] as String,
        };
      }).toList();

      // 進捗ダイアログを一度非表示にする（送信先選択前）
      _hideProgressDialog();

      // 送信先選択ダイアログの表示
      List<Map<String, String>>? selectedRecipients = await _selectRecipients(allRecipients);
      if (selectedRecipients == null || selectedRecipients.isEmpty) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('送信先が選択されませんでした')));
        setState(() {
          _isSending = false;
        });
        return;
      }

      // メール送信処理前に再び進捗ダイアログを表示
      _progressMessageNotifier.value = "メール送信中...";
      _showProgressDialog();

      String username = 'norimasa.hiratsuka@gmail.com'; // Gmailのユーザー名（メールアドレス）
      String password = 'fghmyxdwzvfdjxyl'; // Gmailのパスワードまたはアプリパスワード
      final smtpServer = gmail(username, password);

      // その他設定値の読み込み
      final senderName = prefs.getString(KEY_SENDER_NAME) ?? "";
      final subject = prefs.getString(KEY_SUBJECT) ?? "選択した画像（ZIPファイル添付）";
      final body = prefs.getString(KEY_BODY) ?? "画像をZIPファイルに圧縮して添付しています。";

      final message = Message()
        ..from = Address(username, senderName)
        // 複数の送信先メールアドレスを追加
        ..recipients.addAll(selectedRecipients.map((e) => e['email']!).toList())
        ..subject = subject
        ..text = body
        ..attachments.add(FileAttachment(zipFile));

      final sendReport = await send(message, smtpServer);
      print('メッセージ送信完了: ' + sendReport.toString());
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('メールを送信しました')));
      setState(() {
        _selectedImages = [];
      });
    } catch (error) {
      print('メール送信エラー: $error');
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('メール送信に失敗しました')));
    } finally {
      _hideProgressDialog(); // メール送信完了後に必ず進捗ダイアログを閉じる
      setState(() {
        _isSending = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('画像選択＆メール送信'),
        actions: [
          IconButton(
            icon: Icon(Icons.settings),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => EmailSettingsScreen()),
              );
            },
          )
        ],
      ),
      body: Column(
        children: [
          SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: ElevatedButton(
              onPressed: _pickImages,
              child: Text('画像を選ぶ'),
            ),
          ),
          SizedBox(height: 16),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: GridView.builder(
                padding: EdgeInsets.all(8.0),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: _selectedImages.length,
                itemBuilder: (context, index) {
                  return Image.file(_selectedImages[index], fit: BoxFit.cover);
                },
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: ElevatedButton(
              onPressed: _isSending ? null : _sendEmail,
              child: Text('メールで送る'),
            ),
          ),
          SizedBox(height: 16),
        ],
      ),
    );
  }
}

class EmailSettingsScreen extends StatefulWidget {
  @override
  _EmailSettingsScreenState createState() => _EmailSettingsScreenState();
}

class _EmailSettingsScreenState extends State<EmailSettingsScreen> {
  final _senderController = TextEditingController();
  final _subjectController = TextEditingController();
  final _bodyController = TextEditingController();
  // 送信先リスト：各要素は {'label': String, 'email': String} の形
  List<Map<String, String>> _recipients = [];

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  // 設定値の読み込み（送信者情報・件名・本文および送信先リスト）
  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _senderController.text = prefs.getString(KEY_SENDER_NAME) ?? "";
    _subjectController.text = prefs.getString(KEY_SUBJECT) ?? "ファイル添付";
    _bodyController.text = prefs.getString(KEY_BODY) ?? "画像をZIPファイルに圧縮して添付しています。";
    String? recipientListJson = prefs.getString(KEY_RECIPIENT_LIST);
    if (recipientListJson != null) {
      List<dynamic> jsonList = jsonDecode(recipientListJson);
      _recipients = jsonList.map<Map<String, String>>((item) {
        return {
          'label': item['label'] as String,
          'email': item['email'] as String,
        };
      }).toList();
    }
    setState(() {});
  }

  // 送信先リストの保存
  Future<void> _saveRecipientList() async {
    final prefs = await SharedPreferences.getInstance();
    String encoded = jsonEncode(_recipients);
    await prefs.setString(KEY_RECIPIENT_LIST, encoded);
  }

  // 全設定値（送信者情報・件名・本文および送信先リスト）の保存
  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(KEY_SENDER_NAME, _senderController.text);
    await prefs.setString(KEY_SUBJECT, _subjectController.text);
    await prefs.setString(KEY_BODY, _bodyController.text);
    await _saveRecipientList();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("設定を保存しました")));
  }

  // 送信先追加のためのダイアログ表示
  Future<void> _showAddRecipientDialog() async {
    String label = "";
    String email = "";
    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text("送信先を追加"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                decoration: InputDecoration(labelText: "ラベル"),
                onChanged: (value) {
                  label = value;
                },
              ),
              TextField(
                decoration: InputDecoration(labelText: "メールアドレス"),
                onChanged: (value) {
                  email = value;
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              child: Text("キャンセル"),
              onPressed: () {
                Navigator.pop(context);
              },
            ),
            ElevatedButton(
              child: Text("追加"),
              onPressed: () {
                if (label.isNotEmpty && email.isNotEmpty) {
                  setState(() {
                    _recipients.add({'label': label, 'email': email});
                  });
                  Navigator.pop(context);
                }
              },
            ),
          ],
        );
      },
    );
  }

  // 送信先リスト項目の削除処理
  void _deleteRecipient(int index) {
    setState(() {
      _recipients.removeAt(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("メール設定")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: [
            TextField(
              controller: _senderController,
              decoration: InputDecoration(labelText: "送信者名"),
            ),
            SizedBox(height: 16),
            Text("送信先一覧",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            // 送信先リストの表示
            ListView.builder(
              shrinkWrap: true,
              physics: NeverScrollableScrollPhysics(),
              itemCount: _recipients.length,
              itemBuilder: (context, index) {
                final recipient = _recipients[index];
                return ListTile(
                  title: Text("${recipient['label']} (${recipient['email']})"),
                  trailing: IconButton(
                    icon: Icon(Icons.delete),
                    onPressed: () => _deleteRecipient(index),
                  ),
                );
              },
            ),
            SizedBox(height: 8),
            ElevatedButton(
              onPressed: _showAddRecipientDialog,
              child: Text("送信先を追加"),
            ),
            SizedBox(height: 16),
            TextField(
              controller: _subjectController,
              decoration: InputDecoration(labelText: "件名"),
            ),
            SizedBox(height: 16),
            TextField(
              controller: _bodyController,
              decoration: InputDecoration(labelText: "本文"),
              maxLines: 4,
            ),
            SizedBox(height: 32),
            ElevatedButton(
              onPressed: _saveSettings,
              child: Text("保存"),
            ),
          ],
        ),
      ),
    );
  }
}

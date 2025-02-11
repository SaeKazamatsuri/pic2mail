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

const String KEY_SENDER_NAME = "senderName";
const String KEY_RECIPIENT = "recipient";
const String KEY_SUBJECT = "subject";
const String KEY_BODY = "body";

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

  @override
  void dispose() {
    _progressMessageNotifier.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    final List<XFile>? pickedFiles = await _picker.pickMultiImage();
    if (pickedFiles != null) {
      setState(() {
        _selectedImages = pickedFiles.map((file) => File(file.path)).toList();
      });
    }
  }

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

  void _showProgressDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
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
    );
  }

  Future<void> _sendEmail() async {
    if (_selectedImages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('画像が選択されていません')));
      return;
    }
    if (_isSending) return;
    setState(() { _isSending = true; });

    _progressMessageNotifier.value = "処理を開始します...";
    _showProgressDialog();

    try {
      _progressMessageNotifier.value = "画像を圧縮中...";
      List<File> compressedFiles = [];
      for (File file in _selectedImages) {
        File compressed = await _compressImage(file);
        compressedFiles.add(compressed);
      }

      _progressMessageNotifier.value = "ZIPファイルを作成中...";
      final archive = Archive();
      for (File file in compressedFiles) {
        List<int> fileBytes = await file.readAsBytes();
        String fileName = p.basename(file.path);
        archive.addFile(ArchiveFile(fileName, fileBytes.length, fileBytes));
      }
      List<int>? zipData = ZipEncoder().encode(archive);
      if (zipData == false) throw Exception("ZIPエンコードに失敗しました");
      final tempDir = await getTemporaryDirectory();
      final formattedDate = DateFormat('yyMMdd').format(DateTime.now());
      final zipPath = '${tempDir.path}/images_$formattedDate.zip';
      File zipFile = File(zipPath);
      await zipFile.writeAsBytes(zipData);

      _progressMessageNotifier.value = "ZIPファイルサイズをチェック中...";
      int zipFileSize = await zipFile.length();
      const int maxAttachmentSize = 25 * 1024 * 1024;
      if (zipFileSize > maxAttachmentSize) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('添付ファイルのサイズが25MBを超えています')));
        setState(() { _isSending = false; });
        return;
      }

      _progressMessageNotifier.value = "メール送信中...";
      String username = '';
      String password = '';
      final smtpServer = gmail(username, password);

      // 設定値を読み込み
      final prefs = await SharedPreferences.getInstance();
      final senderName = prefs.getString(KEY_SENDER_NAME) ?? "";
      final recipient = prefs.getString(KEY_RECIPIENT) ?? "";
      final subject = prefs.getString(KEY_SUBJECT) ?? "選択した画像（ZIPファイル添付）";
      final body = prefs.getString(KEY_BODY) ?? "画像をZIPファイルに圧縮して添付しています。";

      final message = Message()
        ..from = Address(username, senderName)
        ..recipients.add(recipient)
        ..subject = subject
        ..text = body
        ..attachments.add(FileAttachment(zipFile));

      final sendReport = await send(message, smtpServer);
      print('メッセージ送信完了: ' + sendReport.toString());
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('メールを送信しました')));
      setState(() { _selectedImages = []; });
    } catch (error) {
      print('メール送信エラー: $error');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('メール送信に失敗しました')));
    } finally {
      Navigator.of(context).pop();
      setState(() { _isSending = false; });
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
  final _recipientController = TextEditingController();
  final _subjectController = TextEditingController();
  final _bodyController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _senderController.text = prefs.getString(KEY_SENDER_NAME) ?? "";
    _recipientController.text = prefs.getString(KEY_RECIPIENT) ?? "";
    _subjectController.text = prefs.getString(KEY_SUBJECT) ?? "ファイル添付";
    _bodyController.text = prefs.getString(KEY_BODY) ?? "画像をZIPファイルに圧縮して添付しています。";
    setState(() {});
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(KEY_SENDER_NAME, _senderController.text);
    await prefs.setString(KEY_RECIPIENT, _recipientController.text);
    await prefs.setString(KEY_SUBJECT, _subjectController.text);
    await prefs.setString(KEY_BODY, _bodyController.text);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("設定を保存しました")));
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
            TextField(
              controller: _recipientController,
              decoration: InputDecoration(labelText: "送信先"),
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

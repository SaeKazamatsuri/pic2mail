# 画像選択＆メール送信アプリ

## 概要
このアプリは、祖父のために作成した画像選択＆メール送信アプリです。複数の画像を選択し、圧縮（ZIP）したうえでメール送信することができます。

## 注意点
- 本アプリは個人用途として作成したものであり、今後のバージョンアップの予定はありません。
- 一部の設定（SMTP情報など）はハードコーディングされているため、使用する際は適宜修正してください。

## 主な機能
- ギャラリーから複数画像を選択
- 画像を圧縮（JPEG品質50％）
- ZIPファイルを作成
- メールで送信（Gmail SMTPを使用）
- 送信者名・宛先・件名・本文を設定可能

## 使用技術
- Flutter 3.27.1
- Dart 3.6.0
- パッケージ:
  - `image_picker`
  - `flutter_image_compress`
  - `archive`
  - `mailer`
  - `shared_preferences`
  - `intl`
  - `path_provider`

## 使い方
1. 「画像を選ぶ」ボタンを押し、送信したい画像を選択する。
2. 「メールで送る」ボタンを押し、メールを送信する。
3. 設定画面で送信者名・宛先・件名・本文を変更可能。

---

# Image Picker & Email Sender App

## Overview
This app was created for my grandfather. It allows users to select multiple images, compress them into a ZIP file, and send them via email.

## Important Notes
- This app was made for personal use and will not receive further updates.
- Some settings (e.g., SMTP details) are hardcoded, so please modify them as needed.

## Features
- Select multiple images from the gallery
- Compress images (JPEG quality 50%)
- Create a ZIP file
- Send email (using Gmail SMTP)
- Configure sender name, recipient, subject, and body

## Technologies Used
- Flutter 3.27.1
- Dart 3.6.0
- Packages:
  - `image_picker`
  - `flutter_image_compress`
  - `archive`
  - `mailer`
  - `shared_preferences`
  - `intl`
  - `path_provider`

## How to Use
1. Tap the "Select Images" button to choose images for sending.
2. Tap the "Send Email" button to send them via email.
3. Modify sender name, recipient, subject, and body in the settings screen.


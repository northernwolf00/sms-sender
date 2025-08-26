import 'dart:convert';
import 'dart:developer';
import 'package:another_telephony/telephony.dart';
import 'package:flutter/material.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const OTPSocketApp());
}

class OTPSocketApp extends StatelessWidget {
  const OTPSocketApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OTP Listener',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const OTPSocketScreen(),
    );
  }
}

class OTPSocketScreen extends StatefulWidget {
  const OTPSocketScreen({super.key});

  @override
  State<OTPSocketScreen> createState() => _OTPSocketScreenState();
}

class _OTPSocketScreenState extends State<OTPSocketScreen> {
  String serverUrl = "http://172.16.18.114:3000";
  String myPhoneNumber = "+99364500768";
  String messageTemplate = "App otp code : {otp}. Verify otp code!";
  String eventName = "send-otp";

  final telephony = Telephony.instance;
  IO.Socket? socket;

  String connectionStatus = "Disconnected";
  Color statusColor = Colors.red;
  List<String> logs = [];

  final TextEditingController serverController = TextEditingController();
  final TextEditingController phoneController = TextEditingController();
  final TextEditingController messageController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  // Load saved settings
  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      serverUrl = prefs.getString('serverUrl') ?? serverUrl;
      myPhoneNumber = prefs.getString('myPhoneNumber') ?? myPhoneNumber;
      messageTemplate = prefs.getString('messageTemplate') ?? messageTemplate;

      serverController.text = serverUrl;
      phoneController.text = myPhoneNumber;
      messageController.text = messageTemplate;
    });
    _connectSocket();
  }

  // Save settings
  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      serverUrl = serverController.text.trim();
      myPhoneNumber = phoneController.text.trim();
      messageTemplate = messageController.text.trim().isEmpty
          ? "App otp code : {otp}. Verify otp code!"
          : messageController.text.trim();
    });

    await prefs.setString('serverUrl', serverUrl);
    await prefs.setString('myPhoneNumber', myPhoneNumber);
    await prefs.setString('messageTemplate', messageTemplate);

    _addLog("⚙️ Settings saved: Server=$serverUrl, Phone=$myPhoneNumber");
    _connectSocket();
  }

  void _connectSocket() {
    socket?.disconnect();

    socket = IO.io(
      serverUrl,
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .enableReconnection()
          .setReconnectionAttempts(9999)
          .setReconnectionDelay(1000)
          .build(),
    );

    socket!.onConnect((_) {
      _addLog("✅ Connected to $serverUrl");
      setState(() {
        connectionStatus = "Connected";
        statusColor = Colors.green;
      });
    });

    socket!.onConnectError((data) {
      _addLog("❌ Connect error: $data");
      setState(() {
        connectionStatus = "Connection Error";
        statusColor = Colors.red;
      });
    });

    socket!.onDisconnect((_) {
      _addLog("🔌 Disconnected");
      setState(() {
        connectionStatus = "Disconnected";
        statusColor = Colors.red;
      });
    });

    socket!.on(eventName, (data) {
      try {
        late Map<String, dynamic> message;
        if (data is Map) {
          message = Map<String, dynamic>.from(data);
        } else if (data is String) {
          message = jsonDecode(data);
        } else {
          _addLog("❌ Unknown data format: $data");
          return;
        }

        final otp = message['otp'].toString();
        final rawPhone = message['phone_number'].toString();
        final formattedPhone =
            rawPhone.startsWith("+993") ? rawPhone : "+993$rawPhone";

        _addLog("📨 OTP Event received: $otp for $formattedPhone");

        // Use dynamic message template
        final msg = messageTemplate.replaceAll("{otp}", otp);

        _sendSMS(msg, formattedPhone);
      } catch (e) {
        _addLog("❌ Failed to parse message: $e");
      }
    });

    socket!.connect();
  }

  void _sendSMS(String message, String phone) async {
    try {
      await telephony.sendSms(to: phone, message: message);
      _addLog("📤 SMS sent to $phone: $message");
    } catch (e) {
      _addLog("❌ SMS send failed: $e");
    }
  }

  void _addLog(String message) {
    final timestamp = DateTime.now().toString().substring(11, 19);
    setState(() {
      log("[$timestamp] $message");
      logs.add("[$timestamp] $message");
      if (logs.length > 50) logs.removeAt(0);
    });
  }

  void _disconnect() {
    socket?.disconnect();
    setState(() {
      connectionStatus = "Disconnected";
      statusColor = Colors.red;
    });
    _addLog("🔌 Disconnected manually");
  }

  @override
  void dispose() {
    socket?.disconnect();
    serverController.dispose();
    phoneController.dispose();
    messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('OTP Listener')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Settings Card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      const Text(
                        "Settings",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: serverController,
                        decoration: const InputDecoration(
                          labelText: 'Server URL',
                          border: OutlineInputBorder(),
                          hintText: 'http://172.16.18.114:3000',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: phoneController,
                        decoration: const InputDecoration(
                          labelText: 'Your Phone Number',
                          border: OutlineInputBorder(),
                          hintText: '+993654321',
                        ),
                        keyboardType: TextInputType.phone,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: messageController,
                        decoration: const InputDecoration(
                          labelText: 'Message Template',
                          border: OutlineInputBorder(),
                          hintText: 'App otp code : {otp}. Verify otp code!',
                        ),
                        maxLines: 2,
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: _saveSettings,
                        child: const Text("Save Settings & Reconnect"),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Connection status
              Card(
                child: ListTile(
                  leading: Icon(Icons.wifi, color: statusColor),
                  title: Text("Status: $connectionStatus"),
                  trailing: ElevatedButton(
                    onPressed:
                        connectionStatus == "Connected" ? _disconnect : null,
                    child: const Text("Disconnect"),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Logs
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: logs.isEmpty
                      ? const Center(child: Text("No logs yet..."))
                      : ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: logs.length,
                          itemBuilder: (context, index) {
                            final log = logs[index];
                            Color color = Colors.black;
                            if (log.contains('❌')) color = Colors.red;
                            if (log.contains('✅')) color = Colors.green;
                            if (log.contains('📤')) color = Colors.blue;
                            if (log.contains('📨')) color = Colors.orange;
                            return Text(
                              log,
                              style: TextStyle(
                                color: color,
                                fontFamily: 'monospace',
                              ),
                            );
                          },
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

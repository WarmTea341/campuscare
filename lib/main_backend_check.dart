// THROWAWAY: proves the real app wiring (Supabase session, persistence, role lookup).
// Run:  flutter run -t lib/main_backend_check.dart --dart-define-from-file=env.json
// Delete this file when the real UI exists.
import 'package:flutter/material.dart';

import 'app_services.dart';
import 'core/errors/api_exception.dart';
import 'services/auth_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final services = await bootstrapServices();
  runApp(MaterialApp(home: BackendCheckPage(services: services)));
}

class BackendCheckPage extends StatefulWidget {
  final AppServices services;
  const BackendCheckPage({super.key, required this.services});

  @override
  State<BackendCheckPage> createState() => _BackendCheckPageState();
}

class _BackendCheckPageState extends State<BackendCheckPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  String _log = 'Starting...';

  @override
  void initState() {
    super.initState();
    _run(() async {
      final u = await widget.services.auth.restoreSession();
      return u == null ? 'No saved session' : 'Restored session: ${u.fullName} (${u.role.name})';
    });
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _run(Future<String> Function() action) async {
    String result;
    try {
      result = await action();
    } on AuthFailure catch (e) {
      result = 'Login problem: ${e.message}';
    } on ApiException catch (e) {
      result = '${e.userMessage}  [${e.statusCode} ${e.code}]';
    } catch (e) {
      result = 'Unexpected: $e';
    }
    if (!mounted) return;
    setState(() => _log = result);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.services;
    return Scaffold(
      appBar: AppBar(title: const Text('CampusCare backend check')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            TextField(
                controller: _email,
                decoration: const InputDecoration(labelText: 'Email'),
                keyboardType: TextInputType.emailAddress),
            TextField(
                controller: _password,
                decoration: const InputDecoration(labelText: 'Password'),
                obscureText: true),
            const SizedBox(height: 12),
            Wrap(spacing: 8, children: [
              ElevatedButton(
                onPressed: () => _run(() async {
                  final u = await s.auth.signIn(_email.text, _password.text);
                  return 'Signed in: ${u.fullName} (${u.role.name})';
                }),
                child: const Text('Sign in'),
              ),
              ElevatedButton(
                onPressed: () => _run(() async {
                  final list = await s.api.listReports(limit: 5);
                  return list.isEmpty
                      ? 'No reports'
                      : '${list.length} report(s). Latest: ${list.first.displayTitle} [${list.first.status}]';
                }),
                child: const Text('My reports'),
              ),
              ElevatedButton(
                onPressed: () => _run(() async {
                  await s.auth.signOut();
                  return 'Signed out';
                }),
                child: const Text('Sign out'),
              ),
            ]),
            const SizedBox(height: 16),
            SelectableText(_log),
          ],
        ),
      ),
    );
  }
}

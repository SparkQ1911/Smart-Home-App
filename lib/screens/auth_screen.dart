import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/smart_home_provider.dart';
import '../services/api_service.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isRegistering = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SmartHomeProvider>();
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Icon(
                          Icons.home_rounded,
                          size: 52,
                          color: Color(0xFF3867D6),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _isRegistering ? 'Tạo tài khoản' : 'Đăng nhập',
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _isRegistering
                              ? 'Đăng ký để quản lý ngôi nhà thông minh của bạn.'
                              : 'Đăng nhập để tiếp tục quản lý ngôi nhà.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                        if (_isRegistering) ...[
                          TextFormField(
                            controller: _nameController,
                            textCapitalization: TextCapitalization.words,
                            autofillHints: const [AutofillHints.name],
                            decoration: const InputDecoration(
                              labelText: 'Tên hiển thị',
                              prefixIcon: Icon(Icons.person_outline_rounded),
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Vui lòng nhập tên.';
                              }
                              if (value.trim().length > 60) {
                                return 'Tên không được quá 60 ký tự.';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 14),
                        ],
                        TextFormField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const [AutofillHints.email],
                          autocorrect: false,
                          decoration: const InputDecoration(
                            labelText: 'Email',
                            prefixIcon: Icon(Icons.email_outlined),
                          ),
                          validator: (value) {
                            final email = value?.trim() ?? '';
                            if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                                .hasMatch(email)) {
                              return 'Vui lòng nhập email hợp lệ.';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _passwordController,
                          obscureText: true,
                          autofillHints: [
                            _isRegistering
                                ? AutofillHints.newPassword
                                : AutofillHints.password,
                          ],
                          decoration: const InputDecoration(
                            labelText: 'Mật khẩu',
                            prefixIcon: Icon(Icons.lock_outline_rounded),
                          ),
                          validator: (value) {
                            if (value == null || value.length < 8) {
                              return 'Mật khẩu cần ít nhất 8 ký tự.';
                            }
                            if (value.length > 128) {
                              return 'Mật khẩu không được quá 128 ký tự.';
                            }
                            return null;
                          },
                        ),
                        if (_isRegistering) ...[
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _confirmPasswordController,
                            obscureText: true,
                            decoration: const InputDecoration(
                              labelText: 'Nhập lại mật khẩu',
                              prefixIcon: Icon(Icons.lock_reset_rounded),
                            ),
                            validator: (value) {
                              if (value != _passwordController.text) {
                                return 'Mật khẩu nhập lại chưa khớp.';
                              }
                              return null;
                            },
                          ),
                        ],
                        if (_error != null || provider.authError != null) ...[
                          const SizedBox(height: 14),
                          Text(
                            _error ?? provider.authError!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                        const SizedBox(height: 20),
                        FilledButton(
                          onPressed: provider.isAuthBusy ? null : _submit,
                          child: provider.isAuthBusy
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(_isRegistering ? 'Đăng ký' : 'Đăng nhập'),
                        ),
                        TextButton(
                          onPressed: provider.isAuthBusy
                              ? null
                              : () => setState(() {
                                    _isRegistering = !_isRegistering;
                                    _error = null;
                                  }),
                          child: Text(
                            _isRegistering
                                ? 'Đã có tài khoản? Đăng nhập'
                                : 'Chưa có tài khoản? Đăng ký',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _error = null);
    final provider = context.read<SmartHomeProvider>();
    try {
      if (_isRegistering) {
        await provider.register(
          name: _nameController.text.trim(),
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
      } else {
        await provider.login(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
      }
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }
}

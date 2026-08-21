import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/api_service.dart';
import 'document_entry_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() =>
      _LoginScreenState();
}

class _LoginScreenState
    extends State<LoginScreen> {
  final usernameController =
      TextEditingController();

  final passwordController =
      TextEditingController();

  final usernameFocusNode = FocusNode();
  final passwordFocusNode = FocusNode();

  bool obscurePassword = true;
  bool isLoading = false;

  String errorMessage = '';

  final usernameFormatter =
      FilteringTextInputFormatter.allow(
    RegExp(r'[a-zA-Z0-9._\-]'),
  );

  final passwordFormatter =
      FilteringTextInputFormatter.allow(
    RegExp(r'[\x21-\x7E]'),
  );

  @override
  void dispose() {
    usernameController.dispose();
    passwordController.dispose();

    usernameFocusNode.dispose();
    passwordFocusNode.dispose();

    super.dispose();
  }

  Future<void> login() async {
    if (isLoading) {
      return;
    }

    final username =
        usernameController.text.trim();

    final password =
        passwordController.text;

    if (username.isEmpty) {
      setState(() {
        errorMessage =
            'اكتبي اسم المستخدم.';
      });

      usernameFocusNode.requestFocus();
      return;
    }

    if (password.isEmpty) {
      setState(() {
        errorMessage =
            'اكتبي كلمة المرور.';
      });

      passwordFocusNode.requestFocus();
      return;
    }

    FocusScope.of(context).unfocus();

    setState(() {
      isLoading = true;
      errorMessage = '';
    });

    try {
      final response =
          await ApiService.postJson(
        'login.php',
        {
          'username': username,
          'password': password,
        },
        authenticated: false,
      );

      final sessionValue =
          response['session'];

      final session =
          sessionValue is Map
              ? Map<String, dynamic>.from(
                  sessionValue,
                )
              : <String, dynamic>{};

      final token =
          response['token']?.toString() ??
          session['token']?.toString() ??
          '';

      final expiresAt =
          response['expires_at']?.toString() ??
          session['expires_at']?.toString();

      if (token.trim().isEmpty) {
        throw const ApiException(
          'لم يرسل الخادم جلسة دخول صالحة.',
        );
      }

      ApiService.setSession(
        token: token,
        expiresAt: expiresAt,
      );

      final userValue = response['user'];

      final user =
          userValue is Map
              ? Map<String, dynamic>.from(
                  userValue,
                )
              : <String, dynamic>{};

      final mustChangePassword =
          response['must_change_password'] ==
                  true ||
              user['must_change_password'] ==
                  true ||
              user['must_change_password'] ==
                  1;

      if (mustChangePassword) {
        ApiService.clearSession();

        if (!mounted) {
          return;
        }

        setState(() {
          errorMessage =
              'يجب تغيير كلمة المرور الأولية '
              'قبل استخدام التطبيق.';
        });

        return;
      }

      passwordController.clear();

      if (!mounted) {
        return;
      }

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) =>
              const DocumentEntryScreen(),
        ),
      );
    } on ApiException catch (exception) {
      if (!mounted) {
        return;
      }

      setState(() {
        errorMessage = exception.message;
      });

      passwordController.clear();
      passwordFocusNode.requestFocus();
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        errorMessage =
            'حدث خطأ غير متوقع أثناء تسجيل الدخول.';
      });

      passwordController.clear();
      passwordFocusNode.requestFocus();
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  InputDecoration buildInputDecoration({
    required String label,
    required IconData prefixIcon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(prefixIcon),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: const Color(0xFFF8FAFD),
      border: OutlineInputBorder(
        borderRadius:
            BorderRadius.circular(12),
        borderSide: const BorderSide(
          color: Color(0xFFD6E1F0),
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius:
            BorderRadius.circular(12),
        borderSide: const BorderSide(
          color: Color(0xFFD6E1F0),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius:
            BorderRadius.circular(12),
        borderSide: const BorderSide(
          color: Color(0xFF24528A),
          width: 2,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor:
          const Color(0xFFF1F5FA),
      body: Center(
        child: SingleChildScrollView(
          padding:
              const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints:
                const BoxConstraints(
              maxWidth: 420,
            ),
            child: Container(
              padding:
                  const EdgeInsets.all(30),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius:
                    BorderRadius.circular(20),
                border: Border.all(
                  color:
                      const Color(0xFFDDE6F2),
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x14000000),
                    blurRadius: 24,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
              child: AutofillGroup(
                child: Column(
                  mainAxisSize:
                      MainAxisSize.min,
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration:
                          const BoxDecoration(
                        color:
                            Color(0xFFE8F1FC),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.inventory_2_outlined,
                        size: 36,
                        color:
                            Color(0xFF24528A),
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'نظام أرشفة المستندات',
                      textAlign:
                          TextAlign.center,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight:
                            FontWeight.bold,
                        color:
                            Color(0xFF173A64),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'سجّلي الدخول للمتابعة',
                      style: TextStyle(
                        fontSize: 14,
                        color:
                            Color(0xFF65758B),
                      ),
                    ),
                    const SizedBox(height: 28),
                    TextField(
                      controller:
                          usernameController,
                      focusNode:
                          usernameFocusNode,
                      textDirection:
                          TextDirection.ltr,
                      keyboardType:
                          TextInputType.text,
                      autocorrect: false,
                      enableSuggestions:
                          false,
                      autofillHints: const [
                        AutofillHints.username,
                      ],
                      inputFormatters: [
                        usernameFormatter,
                        LengthLimitingTextInputFormatter(
                          80,
                        ),
                      ],
                      textInputAction:
                          TextInputAction.next,
                      onSubmitted: (_) {
                        passwordFocusNode
                            .requestFocus();
                      },
                      decoration:
                          buildInputDecoration(
                        label:
                            'اسم المستخدم',
                        prefixIcon:
                            Icons.person_outline,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller:
                          passwordController,
                      focusNode:
                          passwordFocusNode,
                      textDirection:
                          TextDirection.ltr,
                      keyboardType:
                          TextInputType
                              .visiblePassword,
                      autocorrect: false,
                      enableSuggestions:
                          false,
                      autofillHints: const [
                        AutofillHints.password,
                      ],
                      inputFormatters: [
                        passwordFormatter,
                        LengthLimitingTextInputFormatter(
                          128,
                        ),
                      ],
                      obscureText:
                          obscurePassword,
                      textInputAction:
                          TextInputAction.done,
                      onSubmitted: (_) =>
                          login(),
                      decoration:
                          buildInputDecoration(
                        label:
                            'كلمة المرور',
                        prefixIcon:
                            Icons.lock_outline,
                        suffixIcon:
                            IconButton(
                          tooltip: obscurePassword
                              ? 'إظهار كلمة المرور'
                              : 'إخفاء كلمة المرور',
                          onPressed: isLoading
                              ? null
                              : () {
                                  setState(() {
                                    obscurePassword =
                                        !obscurePassword;
                                  });
                                },
                          icon: Icon(
                            obscurePassword
                                ? Icons
                                    .visibility_off_outlined
                                : Icons
                                    .visibility_outlined,
                          ),
                        ),
                      ),
                    ),
                    if (errorMessage
                        .isNotEmpty) ...[
                      const SizedBox(
                        height: 16,
                      ),
                      Container(
                        width:
                            double.infinity,
                        padding:
                            const EdgeInsets
                                .all(12),
                        decoration:
                            BoxDecoration(
                          color: const Color(
                            0xFFFFECEC,
                          ),
                          borderRadius:
                              BorderRadius
                                  .circular(10),
                        ),
                        child: Text(
                          errorMessage,
                          textAlign:
                              TextAlign.center,
                          style:
                              const TextStyle(
                            color:
                                Color(0xFFB42318),
                            fontWeight:
                                FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 22),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: isLoading
                            ? null
                            : login,
                        style: ElevatedButton
                            .styleFrom(
                          backgroundColor:
                              const Color(
                            0xFF24528A,
                          ),
                          foregroundColor:
                              Colors.white,
                          shape:
                              RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius
                                    .circular(12),
                          ),
                        ),
                        child: isLoading
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child:
                                    CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color:
                                      Colors.white,
                                ),
                              )
                            : const Text(
                                'دخول',
                                style:
                                    TextStyle(
                                  fontSize: 16,
                                  fontWeight:
                                      FontWeight
                                          .bold,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
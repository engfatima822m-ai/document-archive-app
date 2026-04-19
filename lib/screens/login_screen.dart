import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'document_entry_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController usernameController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  String errorMessage = '';

  final String correctUsername = "admin11";
  final String correctPassword = "opdc112233";

  bool obscurePassword = true;

  final FilteringTextInputFormatter englishOnlyFormatter =
      FilteringTextInputFormatter.allow(
    RegExp(r'[a-zA-Z0-9@._\-]'),
  );

  void login() {
    if (usernameController.text.trim() == correctUsername &&
        passwordController.text.trim() == correctPassword) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => const DocumentEntryScreen(),
        ),
      );
    } else {
      setState(() {
        errorMessage = "اسم المستخدم أو كلمة المرور غير صحيحة";
      });
    }
  }

  @override
  void dispose() {
    usernameController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  InputDecoration buildInputDecoration({
    required String label,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
      ),
      suffixIcon: suffixIcon,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: Center(
        child: Container(
          width: 400,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                blurRadius: 10,
                color: Colors.black.withOpacity(0.05),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "تسجيل الدخول",
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),

              TextField(
                controller: usernameController,
                textDirection: TextDirection.ltr,
                keyboardType: TextInputType.text,
                autocorrect: false,
                enableSuggestions: false,
                inputFormatters: [englishOnlyFormatter],
                decoration: buildInputDecoration(
                  label: "اسم المستخدم",
                ),
              ),

              const SizedBox(height: 15),

              TextField(
                controller: passwordController,
                textDirection: TextDirection.ltr,
                keyboardType: TextInputType.visiblePassword,
                autocorrect: false,
                enableSuggestions: false,
                inputFormatters: [englishOnlyFormatter],
                obscureText: obscurePassword,
                decoration: buildInputDecoration(
                  label: "كلمة المرور",
                  suffixIcon: IconButton(
                    onPressed: () {
                      setState(() {
                        obscurePassword = !obscurePassword;
                      });
                    },
                    icon: Icon(
                      obscurePassword
                          ? Icons.visibility_off
                          : Icons.visibility,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              if (errorMessage.isNotEmpty)
                Text(
                  errorMessage,
                  style: const TextStyle(color: Colors.red),
                ),

              const SizedBox(height: 10),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: login,
                  child: const Text("دخول"),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
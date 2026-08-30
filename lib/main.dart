import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:whatsapp_clone/shared/repositories/isar_db.dart';
import 'package:whatsapp_clone/shared/utils/abc.dart';
import 'package:whatsapp_clone/shared/utils/shared_pref.dart';
import 'package:whatsapp_clone/shared/utils/storage_paths.dart';
import 'features/auth/views/welcome.dart';

import 'features/home/views/base.dart';
import 'firebase_options.dart';

import 'package:whatsapp_clone/theme/theme.dart';

import 'package:tencent_calls_uikit/tencent_calls_uikit.dart';

import 'dart:async';

void main() async {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      debugPrint('Flutter Error: ${details.exceptionAsString()}');
    };

    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    } catch (e) {
      debugPrint('Firebase init warning: $e');
    }

    try {
      await SharedPref.init();
    } catch (e) {
      debugPrint('SharedPref init warning: $e');
    }

    try {
      await IsarDb.init();
    } catch (e) {
      debugPrint('IsarDb init warning: $e');
    }

    try {
      await DeviceStorage.init();
    } catch (e) {
      debugPrint('DeviceStorage init warning: $e');
    }

    ErrorWidget.builder = (details) => CustomErrorWidget(details: details);

    runApp(
      const ProviderScope(
        child: WhatsApp(),
      ),
    );
  }, (error, stackTrace) {
    debugPrint('Uncaught root error: $error\n$stackTrace');
  });
}

class WhatsApp extends ConsumerWidget {
  const WhatsApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ScreenUtilInit(
      designSize: const Size(360, 800),
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (context, child) {
        return MaterialApp(
          title: "katschat",
          initialRoute: '/',
          navigatorObservers: [TUICallKit.navigatorObserver],
          theme: ref.read(lightThemeProvider),
          darkTheme: ref.read(darkThemeProvider),
          themeMode: ThemeMode.system,
          debugShowCheckedModeBanner: false,
          home: Builder(
            builder: (BuildContext context) {
              final user = getCurrentUser();
              if (user != null) {
                return HomePage(user: user);
              }
              return const WelcomePage();
            },
          ),
        );
      },
    );
  }
}

class CustomErrorWidget extends StatelessWidget {
  final FlutterErrorDetails details;

  const CustomErrorWidget({
    super.key,
    required this.details,
  });

  @override
  Widget build(BuildContext context) {
    final colorTheme = Theme.of(context).custom.colorTheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(
                height: 25,
              ),
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(150),
                  color: colorTheme.appBarColor,
                ),
                child: Icon(
                  Icons.error_outline_rounded,
                  color: Colors.red[400],
                  size: 50,
                ),
              ),
              const SizedBox(
                height: 25,
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12.0,
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      color: colorTheme.appBarColor,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12.0,
                      ),
                      child: ListView(
                        children: [
                          const SizedBox(
                            height: 20.0,
                          ),
                          Text(
                            'OOPS!',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 20.0,
                              color: Colors.red[400],
                            ),
                          ),
                          const SizedBox(
                            height: 20.0,
                          ),
                          Text(
                            details.toString(),
                            textAlign: TextAlign.start,
                            style: TextStyle(
                              fontSize: 12.0,
                              color: colorTheme.blueColor,
                            ),
                          ),
                        ],
                      ),
                    ),
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

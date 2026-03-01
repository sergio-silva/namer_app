import 'dart:async';

import 'package:english_words/english_words.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart';
import 'screens/login_page.dart';
import 'services/auth_service.dart';
import 'services/notification_service.dart';
import 'state/auth_state.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();
  final authService = AuthService(prefs: prefs);

  NotificationService? notificationService;
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    notificationService = NotificationService();
    await notificationService.initialize();
  } catch (e, st) {
    if (kDebugMode) debugPrint('Firebase init failed: $e\n$st');
  }
  runApp(
    MyApp(
      notificationService: notificationService,
      authService: authService,
      prefs: prefs,
    ),
  );
}

class MyApp extends StatefulWidget {
  const MyApp({
    super.key,
    this.notificationService,
    required this.authService,
    required this.prefs,
  });

  final NotificationService? notificationService;
  final AuthService authService;
  final SharedPreferences prefs;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void dispose() {
    // dispose() is async; fire-and-forget is intentional here since State.dispose()
    // must be synchronous. Subscriptions are cancelled in the background.
    final future = widget.notificationService?.dispose();
    if (future != null) unawaited(future);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) =>
              AuthState(authService: widget.authService)..checkSession(),
        ),
        ChangeNotifierProvider(create: (_) => MyAppState(prefs: widget.prefs)),
      ],
      child: MaterialApp(
        title: 'Namer App',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.lightBlue),
        ),
        home: Consumer<AuthState>(
          builder: (_, authState, _) {
            final Widget child;
            if (authState.isLoading) {
              child = const Scaffold(
                key: ValueKey('loading'),
                body: Center(child: CircularProgressIndicator()),
              );
            } else if (authState.isLoggedIn) {
              child = const MyHomePage(key: ValueKey('home'));
            } else {
              child = const LoginPage(key: ValueKey('login'));
            }
            return AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: child,
            );
          },
        ),
      ),
    );
  }
}

class MyAppState extends ChangeNotifier {
  MyAppState({required SharedPreferences prefs}) : _prefs = prefs {
    _loadFavorites();
  }

  final SharedPreferences _prefs;
  static const _keyFavorites = 'favorites';

  var current = WordPair.random();

  void getNext() {
    current = WordPair.random();
    notifyListeners();
  }

  var favorites = <WordPair>{};

  void _loadFavorites() {
    final stored = _prefs.getStringList(_keyFavorites) ?? [];
    favorites = stored.map((s) {
      final parts = s.split(' ');
      return WordPair(parts[0], parts[1]);
    }).toSet();
  }

  void _saveFavorites() {
    unawaited(_prefs.setStringList(
      _keyFavorites,
      favorites.map((p) => '${p.first} ${p.second}').toList(),
    ));
  }

  void toogleFavorite() {
    if (favorites.contains(current)) {
      favorites.remove(current);
    } else {
      favorites.add(current);
    }
    _saveFavorites();
    notifyListeners();
  }

  void removeFavorite(WordPair pair) {
    favorites.remove(pair);
    _saveFavorites();
    notifyListeners();
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  var selectedIndex = 0;

  Future<void> _handleLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text('You will need to sign in again.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    await context.read<AuthState>().logout();

    if (!mounted) return;
    final error = context.read<AuthState>().errorMessage;
    if (error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
      context.read<AuthState>().clearError();
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget page;

    switch (selectedIndex) {
      case 0:
        page = GeneratorPage();
      case 1:
        page = FavoritesPage();
      default:
        throw UnimplementedError('No widget for $selectedIndex');
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return Scaffold(
          body: Row(
            children: [
              SafeArea(
                child: NavigationRail(
                  extended: constraints.maxWidth >= 600,
                  destinations: [
                    NavigationRailDestination(
                      icon: Icon(Icons.home),
                      label: Text('Home'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.favorite),
                      label: Text('Favorites'),
                    ),
                  ],
                  selectedIndex: selectedIndex,
                  onDestinationSelected: (value) {
                    setState(() {
                      selectedIndex = value;
                    });
                  },
                  trailing: Expanded(
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 16.0),
                        child: constraints.maxWidth >= 600
                            ? TextButton.icon(
                                icon: const Icon(Icons.logout),
                                label: const Text('Log out'),
                                onPressed: _handleLogout,
                              )
                            : IconButton(
                                icon: const Icon(Icons.logout),
                                onPressed: _handleLogout,
                                tooltip: 'Log out',
                              ),
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Container(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  child: page,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class GeneratorPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    var appState = context.watch<MyAppState>();
    var pair = appState.current;

    IconData icon;
    if (appState.favorites.contains(pair)) {
      icon = Icons.favorite;
    } else {
      icon = Icons.favorite_border;
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          BigCard(pair: pair),
          SizedBox(height: 10),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ElevatedButton.icon(
                onPressed: () {
                  appState.toogleFavorite();
                },
                icon: Icon(icon),
                label: Text('Like'),
              ),
              ElevatedButton(
                onPressed: () {
                  appState.getNext();
                },
                child: Text('Next'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class BigCard extends StatelessWidget {
  const BigCard({super.key, required this.pair});

  final WordPair pair;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.displayMedium!.copyWith(
      color: theme.colorScheme.onPrimary,
    );

    return Card(
      color: theme.colorScheme.primary,
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Text(
          pair.asLowerCase,
          style: style,
          semanticsLabel: "${pair.first} ${pair.second}",
        ),
      ),
    );
  }
}

class FavoritesPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    var appState = context.watch<MyAppState>();
    var favorites = appState.favorites;

    if (favorites.isEmpty) {
      return Center(child: Text('No favorites yet.'));
    } else {
      return ListView(
        children: favorites.map((pair) {
          return ListTile(
            leading: Icon(Icons.favorite),
            title: Text(pair.asLowerCase),
            onTap: () => appState.removeFavorite(pair),
          );
        }).toList(),
      );
    }
  }
}

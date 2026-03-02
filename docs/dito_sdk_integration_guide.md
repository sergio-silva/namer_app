# Guia de Integração — Dito SDK para Flutter

Baseado na integração realizada no projeto `namer_app` com `dito_sdk ^3.2.1`.

---

## 1. Instalação

Adicione ao `pubspec.yaml`:

```yaml
dependencies:
  dito_sdk: ^3.2.1
  crypto: ^3.0.0   # necessário para SHA-1 do ID do usuário
```

A dependência `crypto` faz parte do ecossistema Dart e não requer configuração adicional.

---

## 2. Credenciais

Nunca coloque `appKey` e `appSecret` diretamente no código-fonte. Use `--dart-define` em tempo de build/execução:

```bash
flutter run \
  --dart-define=DITO_API_KEY=sua_chave \
  --dart-define=DITO_API_SECRET=seu_segredo
```

Crie um arquivo de acesso centralizado às credenciais:

```dart
// lib/dito_options.dart
class DitoOptions {
  static const String appKey   = String.fromEnvironment('DITO_API_KEY');
  static const String appSecret = String.fromEnvironment('DITO_API_SECRET');
}
```

No CI/CD, passe as variáveis como secrets do pipeline. Para builds de produção via `flutter build`, substitua `flutter run` por `flutter build apk` (ou `ipa`) com os mesmos `--dart-define`.

---

## 3. Encapsule o SDK em um serviço próprio

Não use `DitoSdk` diretamente nas camadas de UI ou estado. Crie uma classe `DitoService` que:

- Receba o `DitoSdk` por injeção de dependência (facilita testes e mocks)
- Centralize todo o tratamento de erros
- Gerencie o ciclo de vida do token FCM e o estado de identificação do usuário

```dart
// lib/services/dito_service.dart
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:dito_sdk/dito_sdk.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

class DitoService {
  DitoService({DitoSdk? sdk}) : _sdk = sdk ?? DitoSdk();

  final DitoSdk _sdk;
  String? _currentToken;
  bool _userIdentified = false;

  // ... métodos detalhados nas seções abaixo
}
```

---

## 4. Ordem de inicialização

### Regra fundamental

O Dito SDK depende do Firebase para receber o token FCM. Inicialize sempre nesta ordem:

```
Firebase.initializeApp()  →  DitoService.initialize()
```

### Onde inicializar

A inicialização deve acontecer em `main()`, **antes** de `runApp()`, logo após a inicialização do Firebase:

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  DitoService? ditoService;

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    ditoService = DitoService();
    await ditoService.initialize(
      appKey: DitoOptions.appKey,
      appSecret: DitoOptions.appSecret,
    );
  } catch (e, st) {
    if (kDebugMode) debugPrint('Inicialização falhou: $e\n$st');
    ditoService = null; // <- ESSENCIAL: veja nota abaixo
  }

  runApp(MyApp(ditoService: ditoService));
}
```

> **Atenção — `ditoService = null` no catch:** se `DitoService()` for instanciado mas `initialize()` lançar uma exceção, o objeto existirá com o SDK interno não inicializado. Qualquer chamada posterior (como `identifyUser`) resultará em `PlatformException(NOT_INITIALIZED)`. Resetar para `null` no catch garante que todas as chamadas subsequentes via `_ditoService?.method()` sejam no-ops seguros em vez de erros silenciosos.

### Dentro do `DitoService.initialize()`

```dart
Future<void> initialize({
  required String appKey,
  required String appSecret,
}) async {
  await _sdk.initialize(appKey: appKey, appSecret: appSecret);
  await _sdk.setDebugMode(enabled: kDebugMode); // logs nativos em debug

  // Notificação que abriu o app a partir do estado encerrado (terminated)
  final initial = await FirebaseMessaging.instance.getInitialMessage();
  if (initial != null) await _handleNotificationClick(initial.data);

  // Notificações que trouxeram o app do background para foreground
  FirebaseMessaging.onMessageOpenedApp.listen((message) async {
    await _handleNotificationClick(message.data);
  });

  // Busca e armazena o token FCM — mas NÃO registra ainda
  // O registro só ocorre após identifyUser() (veja seção 6)
  final token = await FirebaseMessaging.instance.getToken();
  _currentToken = token;

  // Escuta renovações de token: atualiza cache e registra se já identificado
  FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
    _currentToken = newToken;
    if (_userIdentified) await registerToken(newToken);
  });

  // Cliques em notificações in-app da Dito
  DitoSdk.onNotificationClick.listen(
    (event) {
      if (event.deeplink.isEmpty) return;
      // TODO: implementar navegação por deeplink (ex: GoRouter)
    },
    onError: (Object e) {
      if (kDebugMode) debugPrint('DitoService.onNotificationClick error: $e');
    },
  );
}
```

---

## 5. Identificação do usuário

### O parâmetro `id` deve ser SHA-1 do e-mail

A Dito exige que o campo `id` seja o SHA-1 em hex do e-mail do usuário (em minúsculas). Nunca passe o e-mail em texto plano como `id`:

```dart
static String _sha1(String value) =>
    sha1.convert(utf8.encode(value)).toString();
```

### Chamada ao `identify`

```dart
Future<void> identifyUser(UserProfile user) async {
  final id = _sha1(user.email);
  if (kDebugMode) {
    debugPrint('DitoService.identifyUser → id=$id email=${user.email}');
  }
  try {
    await _sdk.identify(
      id: id,
      name: user.name,
      email: user.email,
      customData: {
        'gender': user.gender,
        'city': user.city,
        'birth_date': user.birthDate.toIso8601String(),
        'phone': user.phone,
      },
    );
    if (kDebugMode) debugPrint('DitoService.identifyUser ✓ success');

    // Só registra o token APÓS identificar o usuário (veja seção 6)
    _userIdentified = true;
    if (_currentToken != null) await registerToken(_currentToken!);
  } catch (e) {
    if (kDebugMode) debugPrint('DitoService.identifyUser error: $e');
  }
}
```

### Onde chamar `identifyUser`

Chame em todo fluxo que resulta em um usuário autenticado:

| Fluxo | Momento |
|---|---|
| Login | Após confirmação do backend, antes de navegar |
| Cadastro | Após criação da conta, antes de navegar |
| Sessão restaurada | Na verificação de sessão ao abrir o app (ver nota abaixo) |

> **Sessão persistida:** se o app restaura uma sessão salva (ex: via `SharedPreferences`) sem passar pelo fluxo de login, `identifyUser` também deve ser chamado nesse momento. Caso contrário, o usuário não estará identificado na Dito e o token FCM não será registrado até a próxima vez que ele fizer login manualmente.

### Aguarde `identifyUser` — não use `unawaited`

Como `identifyUser` agora também dispara o `registerToken`, ele não deve ser fire-and-forget. Await garante que ambas as operações completem (ou falhem com log) antes de prosseguir:

```dart
// CORRETO
await _ditoService?.identifyUser(currentUser);

// EVITAR — erros de registro de token seriam silenciados
unawaited(_ditoService?.identifyUser(currentUser));
```

Como `identifyUser` tem seu próprio `try/catch` interno, awaitar não impacta a UX — ele nunca propaga exceções.

---

## 6. Registro do token FCM

### Por que o registro é separado da inicialização

A Dito exige que um usuário esteja identificado antes de associar um device token a ele. Registrar o token durante `initialize()` (antes de qualquer `identify`) resulta em o token ficando solto na plataforma, sem vínculo com nenhum usuário.

### Fluxo correto

```
initialize()          → busca e armazena o token em _currentToken (sem registrar)
identifyUser()        → identifica → registra _currentToken
onTokenRefresh        → atualiza _currentToken → registra somente se _userIdentified == true
```

```dart
Future<void> registerToken(String token) async {
  if (kDebugMode) debugPrint('DitoService.registerToken → $token');
  try {
    _currentToken = token;
    await _sdk.registerDeviceToken(token);
    if (kDebugMode) debugPrint('DitoService.registerToken ✓ success');
  } catch (e) {
    if (kDebugMode) debugPrint('DitoService.registerToken error: $e');
  }
}
```

A flag `_userIdentified` protege o listener `onTokenRefresh` para que uma renovação de token que ocorra enquanto nenhum usuário está logado não tente registrar no Dito:

```dart
FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
  _currentToken = newToken;
  if (_userIdentified) await registerToken(newToken); // guarda pelo estado
});
```

---

## 7. Logout — desregistro do token

No logout, o token do dispositivo deve ser desvinculado do usuário na Dito **antes** de encerrar a sessão local. Além disso, `_userIdentified` deve ser resetado para evitar que uma renovação de token subsequente registre indevidamente.

```dart
Future<void> unregisterCurrentToken() async {
  _userIdentified = false;      // <- reseta antes de qualquer await
  if (_currentToken == null) return;
  try {
    await _sdk.unregisterDeviceToken(_currentToken!);
    _currentToken = null;
  } catch (e) {
    if (kDebugMode) debugPrint('DitoService.unregisterToken error: $e');
  }
}
```

Na camada de estado/autenticação:

```dart
Future<void> logout() async {
  // Desregistra o token antes de encerrar a sessão local.
  // unawaited é aceitável aqui pois o logout do app não deve
  // ser bloqueado por uma falha de rede na Dito.
  unawaited(_ditoService?.unregisterCurrentToken());
  await _authService.logout();
}
```

---

## 8. Debug e verificação

Ative o modo debug do SDK durante o desenvolvimento. Isso habilita logs nativos (Android/iOS) que incluem os payloads HTTP enviados à API da Dito:

```dart
await _sdk.setDebugMode(enabled: kDebugMode);
```

Sequência esperada no console ao fazer login com sucesso:

```
DitoService: FCM token fetched → <token>
DitoService.identifyUser → id=<sha1> email=<email>
DitoService.identifyUser ✓ success
DitoService.registerToken → <token>
DitoService.registerToken ✓ success
```

Se `identifyUser ✓ success` aparecer mas o usuário não aparecer na plataforma Dito, verifique:
- Se o `id` enviado bate com o SHA-1 do e-mail esperado pela sua configuração na Dito
- Se `appKey` e `appSecret` são os corretos para o ambiente (produção vs. sandbox)
- Os logs nativos do `setDebugMode` para inspecionar a resposta HTTP da API

---

## 9. Checklist de integração

- [ ] `dito_sdk` e `crypto` adicionados ao `pubspec.yaml`
- [ ] Credenciais via `--dart-define`, nunca hardcoded
- [ ] Firebase inicializado **antes** do `DitoService.initialize()`
- [ ] `ditoService = null` no bloco `catch` de `main()`
- [ ] `setDebugMode(enabled: kDebugMode)` chamado logo após `initialize()`
- [ ] `id` passado ao `identify()` é SHA-1 hex do e-mail
- [ ] Token FCM **não** registrado durante `initialize()` — apenas cacheado
- [ ] `registerToken()` chamado dentro de `identifyUser()`, após sucesso do `identify`
- [ ] `identifyUser()` chamado nos fluxos de login, cadastro **e** restauração de sessão
- [ ] `identifyUser()` é awaited, não fire-and-forget
- [ ] `unregisterCurrentToken()` chamado no logout, reseta `_userIdentified = false`
- [ ] Listener `onTokenRefresh` verifica `_userIdentified` antes de registrar

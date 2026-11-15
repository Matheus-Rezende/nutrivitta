import 'dart:async';

import 'package:flutter/material.dart';

import '../cloud/account.dart';
import 'brand.dart';
import 'common.dart';

enum _Mode { signIn, register, reset }

/// Entrar, criar conta e recuperar a senha (e-mail e senha).
///
/// Usada como tela inicial dos dois apps e, no app do paciente, também aberta
/// por cima do app (modo sem conta). Com [closeOnSuccess], fecha sozinha
/// quando a conta entra.
class AuthScreen extends StatefulWidget {
  const AuthScreen({
    super.key,
    required this.intro,
    this.pro = false,
    this.footer = const [],
    this.closeOnSuccess = false,
  });

  /// Texto curto que apresenta o app.
  final String intro;
  final bool pro;

  /// Itens abaixo do formulário (ex.: usar sem conta).
  final List<Widget> footer;
  final bool closeOnSuccess;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  var _mode = _Mode.signIn;
  var _hidden = true;
  String? _error;
  String? _info;

  Account get _account => Account.instance;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _switch(_Mode m) {
    setState(() {
      _mode = m;
      _error = null;
      _info = null;
      _password.clear();
      _confirm.clear();
    });
  }

  static bool _validEmail(String v) => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.trim());

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() {
      _error = null;
      _info = null;
    });
    String? message;
    switch (_mode) {
      case _Mode.signIn:
        message = await _account.signIn(email: _email.text, password: _password.text);
      case _Mode.register:
        message = await _account.register(name: _name.text, email: _email.text, password: _password.text);
      case _Mode.reset:
        message = await _account.resetPassword(_email.text);
        if (message == null && mounted) {
          setState(() {
            _mode = _Mode.signIn;
            _info = 'Se houver uma conta com ${_email.text.trim()}, enviamos um link para criar uma senha nova. '
                'Confira também a caixa de spam.';
          });
          return;
        }
    }
    if (!mounted) return;
    if (message != null) {
      setState(() => _error = message);
    } else if (widget.closeOnSuccess && _account.signedIn) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final busy = _account.busy;
    final title = switch (_mode) {
      _Mode.signIn => 'Entrar',
      _Mode.register => 'Criar conta',
      _Mode.reset => 'Esqueci minha senha',
    };
    return Scaffold(
      appBar: widget.closeOnSuccess || _mode == _Mode.reset
          ? AppBar(
              leading: _mode == _Mode.reset
                  ? IconButton(
                      icon: const Icon(Icons.arrow_back_rounded),
                      tooltip: 'Voltar',
                      onPressed: () => _switch(_Mode.signIn),
                    )
                  : null,
            )
          : null,
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _account,
          builder: (context, _) => Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Form(
                  key: _form,
                  child: AutofillGroup(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Center(child: NvLogo(size: 80)),
                        const SizedBox(height: 16),
                        Center(child: NvWordmark(size: 34, pro: widget.pro)),
                        if (_mode != _Mode.reset) ...[
                          const SizedBox(height: 10),
                          Text(widget.intro,
                              textAlign: TextAlign.center,
                              style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
                        ],
                        const SizedBox(height: 24),
                        if (_mode == _Mode.reset)
                          Text(title, style: text.titleLarge)
                        else
                          SegmentedButton<_Mode>(
                            segments: const [
                              ButtonSegment(value: _Mode.signIn, label: Text('Entrar')),
                              ButtonSegment(value: _Mode.register, label: Text('Criar conta')),
                            ],
                            selected: {_mode},
                            showSelectedIcon: false,
                            onSelectionChanged: busy ? null : (s) => _switch(s.first),
                          ),
                        const SizedBox(height: 20),
                        if (_mode == _Mode.reset) ...[
                          Text('Digite o e-mail da sua conta. Vamos enviar um link para você criar uma senha nova.',
                              style: text.bodyMedium),
                          const SizedBox(height: 16),
                        ],
                        if (_mode == _Mode.register) ...[
                          TextFormField(
                            controller: _name,
                            textCapitalization: TextCapitalization.words,
                            textInputAction: TextInputAction.next,
                            autofillHints: const [AutofillHints.name],
                            decoration: const InputDecoration(labelText: 'Nome', prefixIcon: Icon(Icons.person_outline)),
                            validator: (v) => (v ?? '').trim().isEmpty ? 'Informe o seu nome.' : null,
                          ),
                          const SizedBox(height: 12),
                        ],
                        TextFormField(
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          autocorrect: false,
                          textInputAction: _mode == _Mode.reset ? TextInputAction.done : TextInputAction.next,
                          autofillHints: const [AutofillHints.email],
                          decoration: const InputDecoration(labelText: 'E-mail', prefixIcon: Icon(Icons.mail_outline)),
                          validator: (v) => _validEmail(v ?? '') ? null : 'Digite um e-mail válido.',
                          onFieldSubmitted: _mode == _Mode.reset ? (_) => _submit() : null,
                        ),
                        if (_mode != _Mode.reset) ...[
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _password,
                            obscureText: _hidden,
                            autocorrect: false,
                            enableSuggestions: false,
                            textInputAction: _mode == _Mode.register ? TextInputAction.next : TextInputAction.done,
                            autofillHints: [_mode == _Mode.register ? AutofillHints.newPassword : AutofillHints.password],
                            decoration: InputDecoration(
                              labelText: 'Senha',
                              helperText: _mode == _Mode.register ? 'Pelo menos ${Account.minPassword} caracteres' : null,
                              prefixIcon: const Icon(Icons.lock_outline),
                              suffixIcon: IconButton(
                                icon: Icon(_hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                                tooltip: _hidden ? 'Mostrar senha' : 'Esconder senha',
                                onPressed: () => setState(() => _hidden = !_hidden),
                              ),
                            ),
                            validator: (v) {
                              final s = v ?? '';
                              if (s.isEmpty) return 'Digite a senha.';
                              if (_mode == _Mode.register && s.length < Account.minPassword) {
                                return 'Use pelo menos ${Account.minPassword} caracteres.';
                              }
                              return null;
                            },
                            onFieldSubmitted: _mode == _Mode.signIn ? (_) => _submit() : null,
                          ),
                        ],
                        if (_mode == _Mode.register) ...[
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _confirm,
                            obscureText: _hidden,
                            autocorrect: false,
                            enableSuggestions: false,
                            textInputAction: TextInputAction.done,
                            decoration:
                                const InputDecoration(labelText: 'Repita a senha', prefixIcon: Icon(Icons.lock_outline)),
                            validator: (v) => v == _password.text ? null : 'As senhas não são iguais.',
                            onFieldSubmitted: (_) => _submit(),
                          ),
                        ],
                        if (_mode == _Mode.signIn)
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: busy ? null : () => _switch(_Mode.reset),
                              child: const Text('Esqueci minha senha'),
                            ),
                          )
                        else
                          const SizedBox(height: 16),
                        if (_error != null || _account.error != null) ...[
                          Text(_error ?? _account.error!, style: text.bodyMedium?.copyWith(color: scheme.error)),
                          const SizedBox(height: 12),
                        ],
                        if (_info != null) ...[
                          Text(_info!, style: text.bodyMedium?.copyWith(color: scheme.primary)),
                          const SizedBox(height: 12),
                        ],
                        FilledButton(
                          onPressed: busy || !_account.supported ? null : _submit,
                          child: busy
                              ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                              : Text(switch (_mode) {
                                  _Mode.signIn => 'Entrar',
                                  _Mode.register => 'Criar conta',
                                  _Mode.reset => 'Enviar link',
                                }),
                        ),
                        if (_mode == _Mode.register) ...[
                          const SizedBox(height: 12),
                          Text(
                            'Depois de criar a conta, enviamos um link para o seu e-mail. '
                            'O app é liberado assim que você confirmar.',
                            textAlign: TextAlign.center,
                            style: text.bodySmall,
                          ),
                        ],
                        if (!_account.supported) ...[
                          const SizedBox(height: 12),
                          Text('O servidor do NutriVitta ainda não foi configurado neste app (veja CONFIGURACAO.md).',
                              textAlign: TextAlign.center, style: text.bodySmall),
                        ],
                        if (_mode != _Mode.reset && widget.footer.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          ...widget.footer,
                        ],
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
}

/// Aguarda a confirmação do e-mail. Confere sozinha a cada poucos segundos e
/// quando o app volta para a frente (a pessoa foi abrir o e-mail).
class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({super.key});

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> with WidgetsBindingObserver {
  Timer? _timer;
  Timer? _cooldownTimer;
  var _cooldown = 0;
  var _checking = false;

  Account get _account => Account.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _account.checkVerified());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _cooldownTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _account.checkVerified();
  }

  Future<void> _check() async {
    setState(() => _checking = true);
    final ok = await _account.checkVerified();
    if (!mounted) return;
    setState(() => _checking = false);
    if (!ok) {
      showSnack(context, 'Ainda não recebemos a confirmação. Toque no link do e-mail e volte aqui.');
    }
  }

  Future<void> _resend() async {
    final message = await _account.resendVerification();
    if (!mounted) return;
    if (message != null) {
      showSnack(context, message);
      return;
    }
    showSnack(context, 'E-mail enviado de novo para ${_account.email}.');
    setState(() => _cooldown = 60);
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _cooldown--);
      if (_cooldown <= 0) t.cancel();
    });
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _account,
          builder: (context, _) => Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(Icons.mark_email_unread_outlined, size: 72, color: scheme.primary),
                    const SizedBox(height: 16),
                    Text('Confirme o seu e-mail', textAlign: TextAlign.center, style: text.headlineSmall),
                    const SizedBox(height: 12),
                    Text.rich(
                      TextSpan(children: [
                        const TextSpan(text: 'Enviamos um link de confirmação para '),
                        TextSpan(text: _account.email, style: const TextStyle(fontWeight: FontWeight.w600)),
                        const TextSpan(
                            text: '. Abra o e-mail e toque no link. Se não encontrar, confira a caixa de spam '
                                'ou promoções.'),
                      ]),
                      textAlign: TextAlign.center,
                      style: text.bodyMedium,
                    ),
                    const SizedBox(height: 8),
                    Text('O app é liberado sozinho assim que o e-mail for confirmado.',
                        textAlign: TextAlign.center, style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _checking ? null : _check,
                      child: _checking
                          ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Já confirmei'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: _account.busy || _cooldown > 0 ? null : _resend,
                      child: Text(_cooldown > 0 ? 'Reenviar e-mail (${_cooldown}s)' : 'Reenviar e-mail'),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _account.busy ? null : () => _account.signOut(),
                      child: const Text('Usar outro e-mail'),
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

/// Envia o link para criar uma senha nova para a conta conectada.
Future<void> changePassword(BuildContext context) async {
  final account = Account.instance;
  final ok = await confirm(context,
      title: 'Mudar a senha?',
      text: 'Vamos enviar para ${account.email} um link para você criar uma senha nova.',
      ok: 'Enviar link');
  if (!ok) return;
  final message = await account.resetPassword(account.email);
  if (context.mounted) {
    showSnack(context, message ?? 'Link enviado para ${account.email}. Confira também a caixa de spam.');
  }
}

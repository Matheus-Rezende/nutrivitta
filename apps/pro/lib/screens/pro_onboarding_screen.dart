import 'package:flutter/material.dart';
import 'package:nutrivitta_core/nutrivitta_core.dart';

import '../pro_state.dart';

/// Cadastro (ou edição) dos dados profissionais.
class ProOnboardingScreen extends StatefulWidget {
  const ProOnboardingScreen({super.key, this.editing = false});

  final bool editing;

  @override
  State<ProOnboardingScreen> createState() => _ProOnboardingScreenState();
}

class _ProOnboardingScreenState extends State<ProOnboardingScreen> {
  late final ProProfile _initial = ProScope.read(context).profile ?? ProProfile(name: Account.instance.name);
  late final _name = TextEditingController(text: _initial.name);
  late final _crn = TextEditingController(text: _initial.crn);
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _crn.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      showSnack(context, 'Informe o seu nome.');
      return;
    }
    setState(() => _saving = true);
    try {
      await ProScope.read(context).saveProfile(ProProfile(name: name, crn: _crn.text.trim()));
      if (mounted && widget.editing) Navigator.pop(context);
    } catch (e) {
      if (mounted) showSnack(context, 'Não foi possível salvar agora. Confira a internet e tente de novo.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.editing ? 'Dados profissionais' : 'Seu perfil profissional'),
        actions: [
          if (!widget.editing) TextButton(onPressed: () => Account.instance.signOut(), child: const Text('Sair')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (!widget.editing) ...[
            Text('Seus pacientes verão estes dados no pedido de conexão.', style: text.bodyMedium),
            const SizedBox(height: 16),
          ],
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Nome', hintText: 'Ex.: Dra. Ana Souza'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _crn,
            decoration: const InputDecoration(labelText: 'CRN (opcional)', hintText: 'Ex.: CRN-3 12345'),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(widget.editing ? 'Salvar' : 'Começar'),
          ),
        ],
      ),
    );
  }
}

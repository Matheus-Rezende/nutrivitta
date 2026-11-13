# NutriVitta

Dois apps Flutter (Android e iOS) que usam o mesmo projeto Firebase:

| App | Para quem | Pacote |
|---|---|---|
| **NutriVitta** (`apps/paciente`) | paciente | `com.nutrivitta.paciente` |
| **NutriVitta Pro** (`apps/pro`) | nutricionista | `com.nutrivitta.pro` |

A parte comum (modelos, acesso à nuvem, tema, componentes de tela, tabela TACO e fontes) fica em `packages/nutrivitta_core`.

## NutriVitta (paciente)

- Registra o que comeu e **quando** comeu (dia e hora), por refeição, com **foto opcional** da refeição.
- Busca em cerca de 600 alimentos brasileiros da tabela TACO, que funciona sem internet, e cadastra alimentos próprios pelo rótulo.
- Vê calorias, proteínas, carboidratos, gorduras, fibras e água do dia contra as metas.
- Resumo de 7 ou 30 dias, histórico de peso e **medidas corporais** (circunferências e % de gordura).
- Preenche a **anamnese**: objetivo, rotina, sono, alimentação, alergias, saúde e medicamentos.
- Recebe o **pedido de conexão** do nutricionista, aceita ou recusa, e pode desconectar quando quiser.
- Recebe notificação de pedido novo e de recado do nutricionista.

## NutriVitta Pro (nutricionista)

- Cria o perfil profissional (nome e CRN).
- Envia o pedido de conexão pelo **e-mail Google** do paciente, com uma mensagem opcional.
- Vê a lista de pacientes conectados, de pedidos aguardando resposta e de recusados.
- Na ficha de cada paciente: diário dia a dia com as fotos, resumo do período, peso, dados do perfil, medidas e anamnese.
- Define as metas do paciente, registra avaliações de medidas, edita a anamnese e deixa um recado por dia.

## Como funciona a conexão

1. O paciente entra no NutriVitta com a conta Google. O app publica o e-mail dele em um diretório para que o nutricionista o encontre.
2. O nutricionista digita esse e-mail no NutriVitta Pro e envia o pedido.
3. O app do paciente mostra o pedido ao abrir e, em segundo plano, confere mais ou menos a cada 15 minutos e mostra uma notificação.
4. Se o paciente aceitar, o uid do nutricionista entra na lista `nutritionistUids` do perfil do paciente. As regras do banco liberam a leitura só para quem está nessa lista, e só o paciente a altera.
5. Qualquer um dos dois pode encerrar o vínculo.

A notificação não é instantânea porque o envio de push pelo Firebase exige um servidor (Cloud Functions), disponível só no plano pago.

## Onde os dados ficam

1. **No aparelho do paciente**: o diário funciona sem internet e sincroniza depois.
2. **Cloud Firestore** (plano gratuito Spark), em São Paulo: perfil, diário, metas, recados, medidas, anamnese, pedidos e fotos. As fotos são comprimidas (cerca de 720 px, 50 KB) e gravadas no próprio banco, porque o Firebase Storage exige o plano pago.
3. **Google Drive do paciente**: cópia de segurança completa, na pasta reservada do app.

Antes do primeiro uso com login, siga o [CONFIGURACAO.md](CONFIGURACAO.md). Sem essa configuração o app do paciente funciona só no aparelho ("Usar sem conta"), e o Pro não entra.

## Estrutura

```
packages/nutrivitta_core/   parte comum
  lib/src/models/           alimentos, diário, paciente (anamnese, medidas), vínculo
  lib/src/cloud/            login Google + Firebase (REST), banco, backup no Drive
  lib/src/widgets/          dia, resumo, peso, medidas, anamnese, metas, foto
  assets/                   tabela TACO e fontes Barlow
apps/paciente/              NutriVitta
  lib/state/app_state.dart  dados locais e fila de envio
  lib/sync.dart             sincronização e respostas aos pedidos
  lib/background.dart       verificação em segundo plano e notificações
apps/pro/                   NutriVitta Pro
  lib/pro_state.dart        perfil profissional, pedidos e pacientes
firestore.rules             regras de segurança do banco
tools/make_icons.py         ícones dos dois apps
```

## Rodar

```
cd packages/nutrivitta_core && flutter test
cd apps/paciente && flutter run
cd apps/pro && flutter run
```

## Limites desta versão

- O login Google está ligado só no Android. No iOS os apps compilam; o do paciente funciona no modo local.
- A verificação em segundo plano roda só no Android, e o próprio sistema pode atrasá-la em economia de bateria.
- Editar o diário no mesmo dia em dois aparelhos ao mesmo tempo não é mesclado: vale o último envio.
- Dados de alimentação e saúde são sensíveis pela LGPD. Antes de usar com pacientes reais, os apps precisam de política de privacidade e termo de consentimento.

## Créditos

Valores nutricionais: Tabela Brasileira de Composição de Alimentos (TACO), 4ª edição, NEPA/UNICAMP, 2011. Dados em CSV do projeto [taco-api](https://github.com/raulfdm/taco-api) (licença MIT). Fontes Barlow (licença OFL).

Os apps ajudam no acompanhamento alimentar e não substituem a consulta com um profissional de saúde.

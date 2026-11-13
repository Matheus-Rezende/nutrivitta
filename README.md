# NutriVitta

Diário alimentar e calculadora de calorias para pacientes e nutricionistas, em Flutter (Android e iOS).

## O que o app faz

**Paciente**
- Registra o que comeu e **quando** comeu (dia e hora), por refeição: café da manhã, lanches, almoço, jantar e ceia.
- Busca em cerca de 600 alimentos brasileiros da tabela TACO, que funciona sem internet, e cadastra alimentos próprios pelo rótulo, com medida caseira opcional (ex.: "1 fatia" = 30 g).
- Vê calorias, proteínas, carboidratos, gorduras e fibras do dia contra as metas, além do consumo de água.
- Recebe uma sugestão de metas a partir de peso, altura, idade, atividade e objetivo (equação de Mifflin-St Jeor) e pode ajustá-las.
- Acompanha o resumo de 7 ou 30 dias e o histórico de peso.
- Compartilha o diário com o nutricionista digitando o código de convite dele, e pode desfazer o vínculo.

**Nutricionista**
- Cria o perfil profissional e recebe um código de convite.
- Vê a lista de pacientes vinculados e, de cada um, o diário dia a dia (só leitura), o resumo do período, o peso e as medidas.
- Define as metas do paciente e deixa um recado por dia, que aparece no diário do paciente.

## Onde os dados ficam

1. **No aparelho**: tudo é gravado primeiro no celular, então o diário funciona sem internet.
2. **Online (Firebase, plano gratuito)**: o login é com a conta Google; os dados vão para o Cloud Firestore, e é isso que permite a conta online e o acesso do nutricionista.
3. **Google Drive**: uma cópia de segurança completa vai para a pasta reservada do app no Drive da própria pessoa (`appDataFolder`), que só o NutriVitta enxerga.

Ao entrar com a conta em um aparelho novo, o app restaura os dados do Firestore e, se não houver, da cópia do Drive.

O projeto é independente do GM Fitness: usa um projeto Firebase/Google próprio. Antes do primeiro uso com login, siga o [CONFIGURACAO.md](CONFIGURACAO.md). Sem essa configuração o app abre e funciona só no aparelho ("Usar sem conta").

## Estrutura

```
lib/
  config.dart            IDs do projeto Google/Firebase (preencher)
  main.dart              abertura e escolha da tela
  models/                alimentos, diário, metas, perfil
  state/app_state.dart   dados locais e fila de envio
  cloud/
    account.dart         login Google + sessão Firebase
    firebase_rest.dart   Firebase Auth e Firestore pela API REST
    remote.dart          leitura e gravação online
    sync.dart            sincronização e cópia no Drive
    drive_backup.dart    arquivo de backup no Google Drive
  screens/               telas do paciente e do nutricionista
  widgets/               componentes compartilhados
assets/foods.json        tabela TACO (gerada de references/csv do projeto taco-api)
firestore.rules          regras de segurança do banco
```

Reaproveitado do GM Fitness: a estrutura do projeto Android/iOS, o tema (com cores próprias), as fontes Barlow, o login Google, o backup no Drive e o fluxo de compilação no GitHub Actions.

## Rodar

```
flutter pub get
flutter test
flutter run
```

## Limites desta primeira versão

- O login Google está ligado no Android. No iOS o app compila e funciona no modo local; o login exige configurar o cliente iOS no Xcode.
- Editar o diário no mesmo dia em dois aparelhos ao mesmo tempo não é mesclado: vale o último envio.
- Ainda não há plano alimentar prescrito pelo nutricionista, leitura de código de barras nem foto das refeições.
- Dados de alimentação e saúde são dados pessoais sensíveis pela LGPD. Antes de publicar para pacientes reais, o app precisa de política de privacidade e termo de consentimento.

## Créditos

Valores nutricionais: Tabela Brasileira de Composição de Alimentos (TACO), 4ª edição, NEPA/UNICAMP, 2011. Dados em CSV do projeto [taco-api](https://github.com/raulfdm/taco-api) (licença MIT). Fontes Barlow (licença OFL).

O NutriVitta ajuda no acompanhamento alimentar e não substitui a consulta com um profissional de saúde.

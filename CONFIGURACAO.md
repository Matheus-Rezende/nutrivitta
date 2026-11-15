# Configuração da nuvem do NutriVitta

Os dois apps usam o mesmo projeto Firebase, no plano gratuito **Spark**, que não pede cartão. Não ative o plano Blaze nem o faturamento. Os nomes dos menus podem variar um pouco no console.

## Já feito (13/11/2026)

- Projeto **`nutrivitta`** criado (sem Analytics e sem Gemini).
- **Authentication > E-mail/senha** ativado (14/11/2026). O login com Google, usado até a versão 0.5.1, continua ativado no console, mas os apps não o usam mais.
- **Firestore** criado em `southamerica-east1` (São Paulo), no modo produção.

Valores do projeto (nenhum é secreto):

| Valor | Onde vai | Conteúdo |
|---|---|---|
| ID do projeto | `FIREBASE_PROJECT_ID` | `nutrivitta` |
| Chave de API da Web | `FIREBASE_API_KEY` | Google Cloud > APIs e serviços > Credenciais > "Browser key (auto created by Firebase)" > Exibir chave |

## Falta fazer

### 1. Publicar as regras do banco (feito em 14/11/2026)

Firestore Database > **Regras**: apague o conteúdo, cole o arquivo [`firestore.rules`](firestore.rules) e clique em **Publicar**. Sem isso o app mostra "A nuvem recusou o acesso". A versão que exige e-mail confirmado foi publicada em 14/11/2026.

### 2. Chave de assinatura (feito em 14/11/2026, SHA-1 `69:9F:9E:37:56:FB:DA:B0:1C:39:AB:8D:21:E8:CB:F8:A8:B2:ED:74`)

A mesma chave assina os dois apps e precisa ser sempre a mesma, para que as atualizações instalem por cima.

1. Gere a chave (uma vez só; guarde o arquivo e a senha em local seguro):
   ```
   keytool -genkey -v -keystore nutrivitta.jks -keyalg RSA -keysize 2048 -validity 10000 -alias nutrivitta
   ```
2. Veja o SHA-1:
   ```
   keytool -list -v -keystore nutrivitta.jks -alias nutrivitta
   ```

### 3. Registrar os dois apps Android (feito em 14/11/2026)

Em **Configurações do projeto > Geral > Seus apps > Adicionar app > Android**, duas vezes:

| Nome do pacote | Apelido |
|---|---|
| `com.nutrivitta.paciente` | NutriVitta |
| `com.nutrivitta.pro` | NutriVitta Pro |

Não é preciso baixar o `google-services.json`: os apps usam a API REST. O SHA-1 só era necessário para o login com Google, que saiu na versão 0.6.0.

### 4. E-mails de confirmação e de nova senha

Os apps pedem os e-mails em português. Para mudar o remetente ou o texto, use **Authentication > Modelos** no console. O plano gratuito envia os e-mails sem custo, com limite diário generoso para testes.

### 5. Valores no GitHub

A chave de API e o ID do projeto já estão em `packages/nutrivitta_core/lib/src/config.dart` (não são segredos: vão dentro dos apps; a proteção vem das regras do banco).

No repositório, **Settings > Secrets and variables > Actions > Secrets**, crie:
- `ANDROID_KEYSTORE_PASSWORD`: a senha da chave;
- `ANDROID_KEYSTORE_BASE64`: o arquivo da chave em base64 (Linux: `base64 -w0 nutrivitta.jks`; Windows/PowerShell: `[Convert]::ToBase64String([IO.File]::ReadAllBytes("$HOME\nutrivitta.jks")) | Set-Clipboard`).

O fluxo `.github/workflows/flutter.yml` gera os dois APKs assinados com essa chave. Para compilar na sua máquina, crie `apps/<app>/android/key.properties` (já está no `.gitignore`):
```
storeFile=/caminho/para/nutrivitta.jks
storePassword=SUA_SENHA
keyAlias=nutrivitta
```

## Conferir

1. Instale o **NutriVitta**, toque em **Criar conta**, confirme o e-mail pelo link e faça o cadastro de paciente.
2. Instale o **NutriVitta Pro**, crie outra conta (outro e-mail), confirme, crie o perfil e toque em **Adicionar paciente** com o código que aparece no NutriVitta, em Perfil > Nutricionistas.
3. No NutriVitta, o pedido aparece no topo do diário (e vira notificação em até ~15 min com o app fechado). Aceite.
4. No Pro, puxe a lista para atualizar e abra o paciente: diário, resumo, medidas, anamnese, metas e recado.
5. No console, em **Firestore Database > Dados**, devem aparecer `users`, `codes`, `pros` e `links`.

Se o app disser que o login por e-mail não foi ativado, confira **Authentication > Método de login > E-mail/senha**. Se o link de confirmação não chegar, veja a caixa de spam.

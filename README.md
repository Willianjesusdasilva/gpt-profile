# gpt-profile

Gerenciador local e open source de multiplos perfis para os aplicativos
ChatGPT/Codex no Windows.

> Projeto experimental e nao oficial. Nao possui afiliacao com a OpenAI.

O `gpt-profile` permite salvar uma sessao, alternar entre contas e abrir o
aplicativo com o perfil escolhido:

```powershell
gpt-profile list
gpt-profile open pessoal
gpt-profile open trabalho
```

## Recursos

- salva multiplos perfis localmente;
- troca a sessao ativa com um unico comando;
- preserva alteracoes do perfil atual antes da troca;
- abre o aplicativo automaticamente;
- cria um workspace local compartilhado;
- funciona sem dependencias externas;
- nao envia credenciais ou telemetria para terceiros.

## Como funciona

O aplicativo oficial usa um container MSIX para armazenar cookies,
preferencias e dados locais. No Codex desktop, a autenticacao tambem utiliza
`%USERPROFILE%\.codex\auth.json`.

Durante uma troca, o `gpt-profile`:

1. encerra o aplicativo para liberar os arquivos;
2. salva o estado e a credencial do perfil atual;
3. restaura o snapshot do perfil escolhido;
4. inicia o aplicativo novamente.

Os perfis ficam em `%USERPROFILE%\gpt-profile\profiles`. Instalacoes antigas
que usam `%USERPROFILE%\gtp-profile` continuam funcionando automaticamente.

## Aviso de seguranca

Os snapshots contem credenciais de sessao. Qualquer pessoa com acesso a eles
pode conseguir acessar suas contas.

- nunca envie a pasta `gpt-profile` para Git, OneDrive ou outro servico;
- nao compartilhe snapshots;
- use apenas em um computador pessoal confiavel;
- remova perfis que nao utiliza mais;
- em caso de exposicao, encerre as sessoes da conta imediatamente.

Consulte [SECURITY.md](SECURITY.md) antes de usar.

## Requisitos

- Windows 10 ou Windows 11;
- aplicativo oficial ChatGPT/Codex instalado pela Microsoft Store;
- Windows PowerShell 5.1 ou PowerShell 7.

## Instalacao

Clone ou baixe este repositorio e execute:

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

Abra um novo terminal e confira:

```powershell
gpt-profile help
```

## Primeiro perfil

Entre na primeira conta pelo aplicativo, feche completamente o app e salve:

```powershell
gpt-profile add pessoal
```

Para atualizar um perfil existente:

```powershell
gpt-profile add pessoal -Force
```

## Segundo perfil

Abra o app:

```powershell
gpt-profile open
```

Saia da conta atual, entre na segunda conta, confirme visualmente a conta,
feche o aplicativo e execute:

```powershell
gpt-profile add trabalho
```

## Alternando perfis

```powershell
gpt-profile open pessoal
gpt-profile open trabalho
```

O comando `switch` e um alias equivalente:

```powershell
gpt-profile switch pessoal
```

## Comandos

| Comando | Descricao |
|---|---|
| `gpt-profile list` | Lista perfis, perfil ativo e armazenamento local |
| `gpt-profile status` | Mostra diagnostico do pacote e caminhos |
| `gpt-profile add <nome>` | Captura a sessao atualmente autenticada |
| `gpt-profile open <nome>` | Ativa o perfil e abre o aplicativo |
| `gpt-profile switch <nome>` | Ativa o perfil e abre o aplicativo |
| `gpt-profile open` | Abre o aplicativo sem trocar de perfil |
| `gpt-profile shared` | Abre o workspace local comum |
| `gpt-profile remove <nome> -Force` | Exclui permanentemente um perfil |
| `gpt-profile help` | Mostra a ajuda |

O ChatGPT nao oferece uma API publica de quotas por conta. Por isso, `list`
mostra o uso de armazenamento local, mas o limite da assinatura deve ser
consultado no aplicativo.

## Workspace compartilhado

```powershell
gpt-profile shared
```

Esse comando abre `%USERPROFILE%\gpt-profile\shared`. Os arquivos dessa pasta
podem ser usados por qualquer perfil, mas chats, memoria, uploads e workspaces
na nuvem continuam vinculados a cada conta. Para compartilhar conteudo cloud,
use um Projeto compartilhado do ChatGPT.

## Limitacoes

- apenas um perfil fica aberto por vez;
- o aplicativo precisa ser reiniciado durante a troca;
- atualizacoes do aplicativo podem mudar seu formato interno;
- quotas da assinatura nao estao disponiveis por API publica;
- perfis criados antes do suporte a `auth.json` precisam ser recapturados.

## Desinstalacao

Remove apenas o comando e preserva os perfis:

```powershell
powershell -ExecutionPolicy Bypass -File .\uninstall.ps1
```

Para excluir tambem todos os snapshots e o workspace compartilhado:

```powershell
powershell -ExecutionPolicy Bypass -File .\uninstall.ps1 -RemoveProfiles
```

Essa segunda operacao e permanente.

## Desenvolvimento e testes

Os testes usam somente diretorios temporarios:

```powershell
powershell -ExecutionPolicy Bypass -File .\tests\run-tests.ps1
```

Veja [CONTRIBUTING.md](CONTRIBUTING.md) para contribuir.

## Creditos

Inspirado no projeto
[`wtfjax/codex-manager`](https://github.com/wtfjax/codex-manager), adaptado
para o aplicativo desktop e seu container MSIX no Windows.

## Licenca

Distribuido sob a licenca MIT. Consulte [LICENSE](LICENSE).

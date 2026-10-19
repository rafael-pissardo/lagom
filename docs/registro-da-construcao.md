# Como a IA foi usada

Registro para o time de tech. As citações são as mensagens do Rafael, na ordem e com a grafia original. A linha em seguida diz só o que a IA fez com aquilo. Não é um resumo das regras de negócio. Essas estão em [planning.md](planning.md).

Ferramenta: Cursor, nesta conversa, de 16 a 19 de outubro de 2026. A primeira mensagem anexou a skill `rails-fullstack-tdd`. Mensagens automáticas do Cursor, como aviso de tarefa em background, não entram.

## Planejamento, antes de código

> /rails-fullstack-tdd Considere: https://sequra.github.io/backend-challenge/
>
> Pensei em fazer uma aplicacao Rails, partindo da versao mais atual (Ruby) tbm. Subir a aplicacao no Railway, com Postgres, SolidQueue. Precisamos ter muito cuidado em seguir as boas praticas do Rails e do Solid, bem como garantir que as migrations e os seeds estao corretos e rodarao em prod.
>
> Considere ainda que teremos 4 ambientes. Test, Development, Staging e Production.
>
> Quero tbm considerar a solucao focada no produto, principalmente as telas.
>
> Se algo nao estiver claro me avise. Nao suponha regras de negocios nem fluxos.
>
> Sobre o banco, quero trabalhar com UUID para ids e normalizar os relacionamentos com o padrao Rails. Por exemplo: tabelas de relacionamento N x N
>
> Tbm quero adicionar indexes para as buscas mais comuns que faremos e para validacoes que tbm estaram presentes nos models.
>
> Qualquer resquest de usuario que possa levar mais de 0.5 segundos, devemos trata-lo de forma async com o SolidQueue e retornar ao usuario que estamos processando.
>
> Todas as requests do front devem retornar notificacao, positiva ou negativa.
>
> Para o front pensei em Tailwind ou Material Design. Avalie qual se encaixa melhor.
>
> Precisamos garantir alguns pontos de seguranca: SQL injections, XSS, CSRF, Cookies e sessões, CORS, Rate Limiting, SSRF.
>
> Testes nao sao opcionais, sao obrigatorios. Quero usar o Rspec. Testes unitarios sao essenciais e testes e2e apenas para cenarios criticos. Use FactoryBot. E faca randomizacao da seed de testes para evitar resultados dependentes da ordem de execucao.
>
> O nome do projeto sera lagom como nome do repositório e Lagom — Merchant Settlement Engine no README.
>
> Lagom eh palavra sueca que representa a ideia de equilíbrio e medida certa. Uma referência à origem sueca do fundador e ao cálculo justo de pagamentos e comissões.
>
> Crie o repositorio no meu workspace pessoal do Git de forma privada.
>
> Me mostre o planejamento antes de atuar no codigo.

16 out 2026, 15:19. A IA leu o desafio e os CSV oficiais e devolveu o plano, sem escrever o app.

> created_on eh o novo padrao rails?

15:04. A IA respondeu que não. A coluna de negócio passou a se chamar `ordered_on`. `created_at` ficou como timestamp do Rails.

> nao tme um nome melhor?

15:05. Correção de nome. `ordered_on` permaneceu.

> Três pontos que a opção A não segura sozinha
>
> Nessa frase supoe que tem uma opcao B, qual seria?

15:06. A IA tirou a ideia de que existia uma opção B. O título do plano virou “Três ajustes em cima da leitura combinada”.

> NAo quero notificação em todo GET.

15:07. O plano passou a limitar flash a POST, PATCH, DELETE, falha e aceite assíncrono.

> Tem algum ajuste aqui? Relógio do backfill. O CSV acaba em 2023-11-07. Se o cron usar “hoje” (2026-10-16), o catch-up de mês zerado criaria mínimos de 2024 até 2026 e dominaria o relatório. O import usa o relógio do arquivo: as_of = maior ordered_on do CSV. Disbursements até esse dia. Monthly fee só para mês já fechado nesse relógio (setembro/2022 até outubro/2023). Novembro/2023 tem pedidos, mas a cobrança só existiria em 2023-12-01, que o arquivo não alcança. O cron ao vivo, depois do deploy, fecha só o dia devido e o mês anterior imediato. Não varre os anos em que o sistema não existia.

15:09. A IA ajustou o relógio: disbursement simulado até 2023-11-14, monthly fee só até outubro de 2023.

> Settlement::Amount fica muito especifica de Settlement. Um modulo de Finance ou algo assim seria melhor para reaproveitarmos o codigo no futuro.

15:14. O módulo de dinheiro virou `Finance::Amount`. As faixas de commission ficaram em `Commission`.

> Remova qualquer referencia da Revelo.

15:16. Menções à Revelo saíram do plano.

> Alem disso, preciso instalar o MissionControll para SolidQueue.

15:17. O plano passou a incluir `mission_control-jobs` em `/jobs`, com a sessão do operador.

> Quero que o rspec trabalhe em modo documentacao

15:18. `.rspec` ficou com `--format documentation`.

> Precisamos de CI CD no Git tbm, com o rspec, rubocop, check de vulnerabilidade e cobertura de teste em pelo menos 95%.
>
> Esses 4 podem rodar em paralelo.

15:27. O plano ganhou quatro jobs paralelos no GitHub Actions. Deploy só depois dos quatro.

> Estamos cobrindo todas as exigencias da descricao da Sequra?

15:29. A IA comparou o plano com o enunciado e apontou o que ainda estava aberto. Não houve código.

> Nao vejo esses pontos como problema:
>
> A reference leva o _ do reference do merchant. O texto diz "alphanumerical", que pode ser só letra e número.
>
> Novembro de 2023 tem pedidos e não tem monthly fee, porque 2023-12-01 não existe no arquivo.
>
> Voce ve?

15:32. A IA concordou e tirou os dois itens da lista de problemas.

> Quanto ao front, gosto bastante do padrao de cores e componenetes do https://railway.com/ Alem disso, tente reaproveitar componentes para facilitar a padronizacao do front o maximo possivel.

15:36. O plano passou a usar a paleta pública do railway.com e um kit de ViewComponents. Sem logo da Railway.

> Como tradeoff no readme, coloque:
>
> - CSVs nao sao salvos num bucket, ainda. Portanto, uma vez processado, perdermos rastreabilidade desse arquivo. Isso entraria como P2 na proxima versao.
> - O servidor do RailsWay eh um servidor hobbysta. Portanto, nao deve aguentar grande carga de dados ou usuarios. Devemos avaliar como a infra ira se comportar. P1 da proxima versao
> - Nao temos nenhum servico de log, como Datadog. Isso eh fundamental. P0 para a proxima versao: contornavel hoje com os logs do servidor.

15:40. Os três tradeoffs entraram no plano e, depois, no README. “RailsWay” foi registrado como Railway Hobby.

> Para o SolidQueue, como teremos apenas um job rodando, podemos deixar as threads e os processos no menor numero possivel.

15:41. Fila configurada com 1 processo e 1 thread.

> No front, precisamos entrar com I18n desde o comeco, em ingles

15:41. UI, flashes e validações passaram a sair de `config/locales/en.yml`.

> Acho que estamos prontos para uma V0

15:42. Aqui a IA saiu do plano e gerou o app. Ruby 4.0.7, Rails 8.1.4, repositório privado `rafael-pissardo/lagom`, commits em `main` até `9e792d1`.

## Depois da V0

> Quero que voce coloque o arquivo de planejamento dentro do projeto e que mostre o link dele no Readme

16 out 2026, 20:53. A IA copiou o plano para `docs/planning.md` e linkou no README. Commit `9e792d1` em `main`. A mesma frase voltou uma vez depois que o contexto da conversa estourou. Não houve um segundo pedido.

> O operador deve ser um usuario da plataforma no sentido de Model. Podemos adicionar o devise de forma simples, sem recuperacao, bloqueio etc. Apenas login e senha.

20:57. A IA trocou o gerador de autenticação do Rails 8 por Devise, só com e-mail e senha.

> operator@lagom.local nao esta na tabela de user by default. Portanto, nao funciona. Ajuste o Readme

21:21. A IA tirou do README a impressão de que esse usuário já existia.

> Faltou configurarmos o cache, queue e cable no database.yml, nao?

21:26. A IA respondeu que não, com o que o código fazia naquele momento: fila no banco principal, cache em memória, cable `async`. Não alterou arquivo.

> O deploy no Railway está falhando com:
>
> ActiveRecord::AdapterNotSpecified: The 'cache' database is not configured for the 'production' environment.

21:30. A IA removeu `database: cache` de `config/cache.yml`.

Ação na interface do Cursor, 21:32: criar branch e commit. Branch `cursor/devise-login-and-cache-boot`, commit `b101e6f`.

> Push e Abra PR

21:33. Push e [pull request #1](https://github.com/rafael-pissardo/lagom/pull/1).

> spec/spec_helper.rb:52:1: C: [Correctable] Layout/TrailingEmptyLines: 1 trailing blank lines detected.
>
> Comite e push

21:35. A IA apagou a linha em branco e enviou o commit `677cc75` no mesmo pull request.

> Quero que o seed rode em producao, tbm

21:51. A IA fez o entrypoint e o `railway.toml` rodarem `db:prepare db:seed` em todo boot.

> Nao faz sentido essa dependencia: OPERATOR_EMAIL e OPERATOR_PASSWORD precisam estar definidos no Railway. Sem essas variáveis o seed falha e o deploy para.

21:56. A IA tirou a obrigatoriedade. Sem as variáveis, o seed usa `operator@lagom.local` e `lagom-operator-password`.

Ação na interface do Cursor, 21:59: commit e push. O commit `50c0755` foi parar no pull request #1.

> Nao, abra em uma nova branch e novo PR

22:07. A IA reverteu esse commit no #1 e abriu o [pull request #2](https://github.com/rafael-pissardo/lagom/pull/2), branch `cursor/seed-operator-in-production`.

> Quero salvar essa nossa conversa em algum arquivo dentro do projeto para fins de verificacao do time de tech. Pensei em salvar o transcript puro, consegue fazer algo mais bonito?

19 out 2026, 11:31. A IA escreveu um resumo das decisões de produto. Não era o uso da IA.

> Entao, eh que eu quero registrar exatamente como usei a IA

11:32. Esta versão do arquivo substitui aquele resumo.

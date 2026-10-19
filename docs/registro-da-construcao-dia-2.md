# Como a IA foi usada — dia 2

Continuação de [registro-da-construcao.md](registro-da-construcao.md). Mesma regra: as citações são as mensagens do Rafael, na ordem e com a grafia original. A linha em seguida diz só o que a IA fez. Não é um resumo das regras de negócio.

Ferramenta: Cursor, nesta conversa, 19 de outubro de 2026, a partir de “Vamos para o dia 2”. Mensagens automáticas do Cursor, como aviso de tarefa em background, não entram. Frase repetida na mesma hora conta uma vez.

## Importação pelo bucket

> Vamos para o dia 2 do desafio da Sequra.
>
> Percebi alguns pontos:
>
> - O fato de termos uma tela de upload de CSVs de merchant e order nao faz uma experiencia muito boa para o usuario.
>   - Talvez podemos ter um dropdown com o tipo da importacao:
>     - Merchant
>     - Orders
>   - Alem disso, adicionei um servico de Bucket estilo S3.
>     - Precisamos salvar esse arquivo no bucket antes de tudo. Alterando seu nome pela concatenacao tipo + timestamp.
>     - Apos salvar, podemos acionar um servico assincrono e devolver ao usuaria que o csv esta sendo processado.
>     - Esse servico sincrono deve consultar o CSV em lotes de 500 em 500, configuraveis via env.
>     - Faca todo processamento do CSV em uma transaction, assim se falhar nenhum item sera adicionado no banco.
>     - Se um erro for encontrado, guarde em um array de erros para mostrar ao usuario em forma de TXT, simples. Contendo a linha e coluna com erro.
>     - Alem disso, precisamos ter o status de processing.

19 out 2026, 13:16. A IA trocou os dois uploads por um dropdown Merchant/Orders. O arquivo vai para o bucket antes do registro, com a chave `{kind}-{timestamp}.csv`. O job é assíncrono, lê em lotes de 500 (`CSV_IMPORT_BATCH_SIZE`), escreve numa transaction e, se uma linha falha, desfaz o arquivo inteiro. O erro vira um TXT com linha e coluna. O status passa a incluir `processing`.

> Essas sao as envs do bucket:

13:21. A mensagem veio com um print: `AWS_ACCESS_KEY_ID`, `AWS_DEFAULT_REGION`, `AWS_ENDPOINT_URL`, `AWS_S3_BUCKET_NAME`, `AWS_SECRET_ACCESS_KEY`. A IA usou esses nomes no cliente do bucket. No desenvolvimento, sem elas, aponta para o MinIO local.

> Pensei em usar o Strategy Pattern para ImportCsv

13:38. A IA separou a importação em estratégias de merchants e de orders.

> Comite, push e abra o PR mirando na main

13:43. [Pull request #5](https://github.com/rafael-pissardo/lagom/pull/5).

> Nos controllers falta a logica de permit dos params para evitar SQL injection, nao?

14:07. A IA respondeu sobre o único payload de escrita, o do import.

> Se usarmos enum, esses metodos veem automaticamente, nao?  def merchants?
>     kind == "merchants"
>   end
>
>   def orders?
>     kind == "orders"
>   end

14:09. A IA confirmou que o enum do Rails gera esses predicados.

> Faca

14:11. A IA trocou os métodos manuais pelo enum de string.

> Use permit nos controllers, sempre.

14:13. A frase chegou duas vezes. A IA usou `params.expect` no import, o strong parameters do Rails 8. Os index não recebem massa de atributos; leem a query string um campo por vez.

> A UX nao esta boa no botao de upload. Bloqueie o botao de start import enquanto um type nao for selecionado e o arquivo nao tiver sido carregado

14:19. O botão fica desabilitado até haver tipo e arquivo.

> Comit push e abra PR

14:19. [Pull request #6](https://github.com/rafael-pissardo/lagom/pull/6).

> Agora vamos atacar um problema com o MissionControl. Ao acessar /jobs, estou recebendo erro 401, mesmo estando logado. Sei que na doc tem um trecho explicando como usar Devise e MissionControl. Corrija

14:26. A frase chegou duas vezes. A IA desligou o HTTP basic do Mission Control e deixou a sessão do Devise na frente. `/jobs` continua exigindo o operador.

> Comite push e abra PR

14:31. [Pull request #7](https://github.com/rafael-pissardo/lagom/pull/7).

> O upload precisa acontecer com multi-part.
> O Refresh do Import Status deve acontecer apenas no show do csv_imports

14:35. O formulário passou a `multipart`. O refresh do status ficou só na show de um import ainda em andamento.

> Quero um logo mais bonito e hypado. Nao faco ideia...sugira algo

14:48. A IA sugeriu uma marca no lugar do ponto vermelho.

> Comite e abra o PR

14:48. [Pull request #8](https://github.com/rafael-pissardo/lagom/pull/8), o upload multipart e o refresh só na show.

> Faca

14:51. A IA aplicou a marca sugerida.

> commit e push

14:56. Commit da marca na branch nova.

> abra o PR

15:04. [Pull request #9](https://github.com/rafael-pissardo/lagom/pull/9).

## CSV grande

> Agora, vamos atacar o problema de processamento para csvs grandes.
>
> - Hoje temos alguns prontos criticos no codigo:
> - Uma consulta para encontrar o merchant.
> - Uma consulta para descobrir se o pedido já existe.
> - Uma operação de INSERT ou UPDATE, quando necessária.
> - Validações do Active Record.
>
> Quero:
>
> - Fazer chache dos merchants ja buscados.
> - quero um validação antecipada do CSV, preservando mensagens de erro, linhas e atomicidade.
> - apos isso quero fazer upsert_all ao inves de adicionar um a um (uma vez passado pelo validador, garantimos que podemos fazer upsert_all)

15:18. A IA colocou cache de merchants, uma validação do arquivo antes da escrita e `upsert_all` no lugar do insert linha a linha.

> Comite push e abra o PR

15:26. [Pull request #10](https://github.com/rafael-pissardo/lagom/pull/10).

> Aqui https://github.com/rafael-pissardo/lagom/pull/10/changes#diff-7384ed00895e21761b5ec1708bdb1f3fe2921e61403ddc70aca73c6644fffbc6R14 podemos usar a gema:https://rubygems.org/gems/uuid para validar, nao?

15:32. A IA não adicionou a gem `uuid`.

> Entao podemos colocar isso num helper? Assim podemos reaproveitar se necessario

15:34. O formato foi para `UuidHelper`.

> No merchant_cache ao importar 1 milhão de merchants novos com referências diferentes, ainda podemos executar aproximadamente 1 milhão de SELECTs.
>
> O cache beneficia referências repetidas, mas não elimina o N+1 de referências inéditas.
>
> Minha sugestão seria buscar referências existentes em lotes:
>
> existing = Merchant
>   .where(reference: references)
>   .pluck(:reference, :id)
>   .to_h
>
> Depois, realizar a validação com essas informações. Para preservar corretamente as mudanças de referências, também será necessário consultar os IDs existentes e acompanhar as alterações feitas dentro do arquivo.

15:38. A frase chegou duas vezes. A IA passou a buscar as referências do lote de uma vez e a acompanhar a troca de reference dentro do arquivo.

> imagine que existe no banco:
>
> ID	Reference
> A	merchant_old
>
> E o CSV contém:
>
> ID	Reference
> A	merchant_new
> B	merchant_old
>
> Na implementação anterior, isso podia funcionar: primeiro atualizava A, liberando merchant_old, depois criava B.
>
> No PR, a validação rejeitará B incorretamente, porque reference_owner continua enxergando a referência antiga no banco e release_previous_reference não conhece o valor anterior de A quando ele já existia.
>
> Esse cenário merece um teste de regressão específico.

15:44. A IA adicionou esse caso como teste e corrigiu a validação para enxergar a troca dentro do arquivo.

> Quero mover a validação para antes da transação de escrita para reduzir a duração da transação, desde que tratemos corretamente a possibilidade de alterações concorrentes no banco.

15:45. A validação saiu de dentro da transaction de escrita. A escrita ainda revalida e trata conflito.

> No upsert_all de ambas as strategies, adicione: returning: false, afinal nao utilizamos os ids.

15:45. As duas estratégias passaram `returning: false`.

> commit e push

15:56. A frase chegou duas vezes. Commit na branch do #10.

> Tenho alguns pontos:
>
> - Memória constante ou proporcional ao número de merchants distintos: não manter uma estrutura por pedido.
> - Streaming + validação transacional: manter o primeiro passe para detectar erros e revalidar cada linha na escrita, com rollback integral diante de falhas.
> - Proteger pedidos liquidados: impedir mudanças que invalidem dados financeiros já consolidados.

16:09. A IA limitou a memória ao que o lote precisa, manteve o passe de validação e o rollback do arquivo, e bloqueou alteração de pedido já disbursed.

> comite e push

16:22. Commit dessa leva.

> - O CSV é baixado duas vezes do S3...quero baixar uma vez para o Tempfile, validar, executar io.rewind e realizar os upserts usando o mesmo arquivo.
> - calcular e associar os pedidos dentro de uma transação com bloqueios adequados. Também conferir a quantidade de registros efetivamente associados.

16:33. O arquivo passa a ser lido uma vez, com `rewind` entre a validação e a escrita. A associação dos pedidos disbursed ficou na transaction, com lock, e a quantidade associada é conferida.

> Agora, quero simplificar um pouco o codigo:
>
> - Buscar merchants em lote com where(...).index_by
> - guard_concurrent_changes! Priorizar constraints do PostgreSQL e tratar conflitos
> - claim_reference! e release_previous_reference Simplificar a regra de unicidade
> - prepare, attributes, review_batch, upsert: reduzir a quantidade de etapas
> - Controle manual de duplicatas: definir uma regra simples para IDs repetidos

16:37. A IA enxugou esses passos e tirou contadores que não eram mais usados.

> commit e push

16:45. A frase chegou duas vezes. Commit.

> Agora quero forcar nenhuma query N+1 com strict_load

16:56. `ApplicationRecord` passou a recusar lazy load. Onde a view toca o merchant, a query inclui a associação.

> Execute the selected diff-tab commit-and-push action.

19:30. Ação da interface do Cursor. A IA commitou só o strict loading. O resto ficou de fora.

> Comite tudo

19:31. A IA commitou o que ainda estava solto.

> Abra um pr novov

19:31. Um pull request novo, não em cima de um já aberto.

> Abra todos os PRs baseados na main

20:09. [Pull request #11](https://github.com/rafael-pissardo/lagom/pull/11), [pull request #12](https://github.com/rafael-pissardo/lagom/pull/12) e [pull request #13](https://github.com/rafael-pissardo/lagom/pull/13). O #13 é o registro do dia 1, que ainda não tinha sido mergeado.

## Produção e a tela

> https://lagom-production.up.railway.app/csv_imports/f012c6ef-86de-4c89-bdce-19a3b65871ef/errors

20:30. A IA abriu esse endereço. O download do TXT de erros respondia 304.

> Estou tomando erro 304

20:30. A IA tirou o cache dessa resposta: `Cache-Control: no-store` e um ETag novo a cada download.

> commit, push e abra PR

20:36. [Pull request #14](https://github.com/rafael-pissardo/lagom/pull/14).

> Ao subir um arquivo, quero um sinal de loading no botao de Start import

20:46. O botão mostra um spinner e fica `aria-busy` no submit.

> Ainda, ja que estamos alterando front, preciso de paginacao em todos os index. Default 10 paginas. Acho que podemos usar o pagy

20:51. A frase chegou duas vezes. A IA usou o Pagy com 10 registros por página nos cinco index. Não limitou a janela de páginas.

> O menu nao pode conter jobs.

21:03. O link Jobs saiu da sidebar. A rota `/jobs` ficou.

> A tela esta desalinhada. O menu deve ficar o mais a esqueda possivel e a tabela centralizada

21:05. A mensagem veio com um print. A sidebar foi para a esquerda da viewport. A tabela ficou centralizada na coluna que sobra.

> Nas tabelas quero deixar os cabecalhos main humanos. Por exemplo: reference nao significa muita coisa.

21:08. Os cabeçalhos dos index passaram a nomear o que a célula mostra. Merchant, e-mail, data, valor, e o equivalente nas outras listas.

> Quero adicionar filtros nos index, podemos usar o cable para isso, assim conseguimos ter uma resposta mais dinamica sem clicar no botao "filtrar".
>
> Busca por nomes ou email, quero que possa ser partial.
> Busca por data, quero um calendario
> Busca por tags, pode ser um dropdown

21:11. A IA não usou Action Cable aqui. O filtro é um GET com Turbo Frame: texto parcial sem diferenciar maiúsculas, `input type="date"` e um select. Não há botão Filtrar. A IA disse que o cable empurra do servidor para o browser, e que o adapter `async` não atravessa o processo do worker.

> Humanize valores como 131931.34, nao fica legivel
> Humanize data no padrao DD/MM/AAAA

21:19. `131931.34` passou a `131,931.34 €`. As datas da tela passaram a `DD/MM/YYYY`. O campo de filtro continua enviando `YYYY-MM-DD`.

> Comit, push e abra o PR

21:27. [Pull request #15](https://github.com/rafael-pissardo/lagom/pull/15). Paginação, filtros, cabeçalhos, menu, alinhamento, loading e o formato de valor e data.

> nas paginacoes, quero o count total e o 10 per page

21:35. O rodapé passou a `Showing 1–10 of 12 · 10 per page`, também quando cabe numa página.

> Ainda quero adicionar ordenadores nos headers, ASC e DESC

21:37. Cada cabeçalho dos cinco index ganhou ASC e DESC. A ordem anterior da lista continua até o clique.

> Abra um novo PR

21:46. [Pull request #16](https://github.com/rafael-pissardo/lagom/pull/16). O #15 já estava mergeado.

> No order dos headers que setinhas

22:51. ASC e DESC viraram ↑ e ↓. O sentido ativo continua marcado.

> Quero usar o action_cable para atualizar o show do csv_imports, quando ele estiver em processing

22:55. A show assina o stream enquanto o import está `pending` ou `processing` e troca o bloco de status quando o status muda. O polling de 3 segundos saiu. O adapter `async` não entrega do worker para o web, então a IA trocou development, staging e production para Solid Cable, na tabela `solid_cable_messages` do banco principal. O teste ficou no adapter `test`.

> Abra um novo PR com tudo que esta por comitar

23:01. [Pull request #17](https://github.com/rafael-pissardo/lagom/pull/17), com as setas e o Cable.

> Com isso aquele codigo antigo de atualizacao via JS por morrer, nao?

23:06. Sim. O controller `import-status` foi apagado. A show não usa mais esse polling.

> Adicione esse report ao Readme:

23:06. A mensagem veio com o print do yearly report. A IA preencheu a tabela do README com 2022 e 2023.

> Atualize o Readme

23:07. A IA acrescentou Solid Cable, Pagy, o console do operador e o parágrafo do Cable no import. A tabela do relatório ficou.

> comite e push

23:08. Commit no #17.

> Estamos terminando o segundo dia. Vamos fazer um arquivo de auditoria igual fizemos pro primeiro dia?

23:08. Este arquivo.

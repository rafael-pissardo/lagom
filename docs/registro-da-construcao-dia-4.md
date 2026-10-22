# Como a IA foi usada — dia 4

Continuação de [registro-da-construcao-dia-3.md](registro-da-construcao-dia-3.md). Mesma regra: as citações são as mensagens do Rafael, na ordem e com a grafia original. A linha em seguida diz só o que a IA fez. Não é um resumo das regras de negócio.

Ferramenta: Cursor, nesta conversa, de 21 a 22 de outubro de 2026, a partir de “Vamos para o dia 4”. Mensagens automáticas do Cursor, como aviso de tarefa em background, não entram. Frase repetida na mesma hora conta uma vez.

## Polimento

> Vamos para o dia 4 de desenvolvimento do desafio tecnico da Sequra. Estamos na fase de polimento.

21 out 2026, 14:09. A IA leu o ponto em que o dia 3 tinha parado.

> Atualize a main local com a main remota

14:10. A IA atualizou a `main` local com a `origin/main`.

> Pronto. Atualizado com a main. Agora:
>
> Um ponto muito importante que quero garantir nos teste eh a questao da idepotencia. Reprocessamentos de planilha repetida ou dado repetido no meio de dados novos nao podem ser reprocessados. Caso tenhamos dados ja processados na planilha, precisamos falhar o importe e justificar no arquivo de erros.
>
> No caso de jobs, precisamos garantir que eles nao geraram entradas duplicadas das que ja geraram um dia.

14:36. A IA fez o import falhar quando o `id` já está gravado. O TXT diz que a linha já foi processada e não pode entrar de novo. O arquivo inteiro desfaz. Rodar o job de novo no mesmo dia não cria outro disbursement nem outra monthly fee.

> Ontem tinha te falado sobre a terceira casa decimal, como 1.239. Porem, te passei uma informacao errada. Quero sempre arredondar para cima valores como esse.

14:49. `1.239` passou a `1.24` antes da comissão. `1.230` continua `1.23`.

> Tava reavaliando a descricao do problema da sequra e cometi um erro de overengineering. Nao preciso do job de backfill. Apenas de job para merchants diarios e outro para semanais.

15:05. O job de backfill saiu. Ficaram `DailyMerchantsJob` e `WeeklyMerchantsJob`, os dois às 07:00 UTC. O import não liquida.

> Atualize readme e planning

15:13. README e `docs/planning.md` passaram a descrever os dois jobs e o arredondamento para cima.

> Comite push e abra PR

15:25. [Pull request #26](https://github.com/rafael-pissardo/lagom/pull/26).

## Lock do import

> pq isso? https://github.com/rafael-pissardo/lagom/pull/26/changes#diff-e8664af8670018cce41bfe54e06cb7cea626ee89029e2620e3ab4129f3d01e13R22

15:31. A IA explicou a linha do diff que o Rafael apontou.

> Mas em caso de concorrencia isso fica vulneravel

15:34. A IA tratou o caso de dois imports ao mesmo tempo.

> concorrencia = corrida. Dois services rodando ao mesmo tempo

15:34. A frase chegou duas vezes. A IA travou o `id` que está sendo gravado para o segundo import não sobrescrever a linha.

> Commite, push

15:43. Commit e push na branch do #26.

> brakeman falhou

15:45. A chave do lock deixou de ser interpolada no SQL. O Brakeman passou.

> Deixe um comentario no identity lock de algo como:
>
> No Rails, a forma mais idiomática de implementar locks é utilizando with_lock, disponível nativamente no ActiveRecord.
>
> Porém, existe uma diferença importante no seu código:
> - with_lock: bloqueia registros existentes no banco de dados usando SELECT ... FOR UPDATE.
> - pg_advisory_xact_lock: bloqueia chaves lógicas, mesmo quando não existe um registro correspondente.
> Como seu ImportCsvService::IdentityLock usa chaves como "#{namespace}:#{id}", não é possível substituí-lo diretamente por with_lock sem mudar o comportamento.
>
> Em infles

15:49. A IA escreveu esse comentário em inglês.

> Ou na verdade, podemos usar essa gem: https://rubygems.org/gems/with_advisory_lock

15:50. A IA trocou o SQL manual pela gem `with_advisory_lock`.

> Podemos remover os comentarios entao

15:52. Os comentários saíram.

> Execute the selected diff-tab commit-and-push action.

15:52. Commit e push na branch do #26.

> nesse cenario de lock, temos um risco elevado de esgotar a memória compartilhada destinada a locks e abortar a importação...substituiria esse mecanismo por um lock por importação, ou por um lock de escopo adequado à operação

16:00. O lock deixou de ser um por `id`. Passou a ser um por tipo de import (`merchants` ou `orders`).

## Dias pendentes e taxa atrasada

> Em um import novo executado em outubro de 2026, os merchants históricos começam em 2022 ou 2023. Quero processar apenas datas elegíveis com pedidos pendentes, em lotes, e usar agregações no PostgreSQL sempre que possível. Hoje a gente passa data a data

16:03. O disbursement passou a olhar só os dias que ainda têm pedido pendente, em lotes. A soma ficou no PostgreSQL.

> Outro edge case: Se uma nova importação incluir pedidos de um mês que já teve sua taxa mínima calculada, o registro anterior não é atualizado. A verificação de existência simplesmente interrompe o cálculo.
>
> Isso compromete a correção financeira do sistema quando há dados atrasados.

16:13. A fee já gravada não é reescrita. O que chega depois vira ajuste.

> Adicione nos relatorio anuais uma coluna que indica a somatoria dos monthly_fee_adjustments e o total deve ser charged_cents + monthly_fee_adjustments

16:24. O relatório anual ganhou a coluna de ajustes. O total somava o crédito em cima do valor cobrado.

> no relatório anual a soma dos ajustes eh sempre referente ao mes em que ajuste ocorreu

16:27. A soma dos ajustes ficou no ano em que o ajuste foi gravado.

> Um import em outubro de 2026 com pedidos de 2022 gera disbursements, mas não gera mensalidades de 2022, mas o ajuste precisa entrar na proxima mensalidade

16:29. Pedido de um mês que nunca teve fee própria passou a reduzir a fee seguinte, num ajuste `carried`. Mês que já tem fee guarda o crédito à parte.

> atualize com a main. comite, push e abra pr

16:34. [Pull request #27](https://github.com/rafael-pissardo/lagom/pull/27).

> rubocp falhou

16:37. A IA corrigiu o RuboCop. O arquivo da migration ganhou a quebra de linha final.

## Cada mês com a própria comissão

> setembro de 2022 gerou € 40 em comissões, setembro de 2026 gerou € 0, e o mínimo é € 29. A taxa de setembro de 2026 deveria ser € 29, independentemente das comissões de 2022. Atualmente, elas podem zerar essa cobrança.

16:45. A frase chegou duas vezes. A fee de um mês passou a usar só a comissão daquele mês. Setembro de 2026 com € 0 fica nos € 29.

> Se uma taxa calculada de € 100 receber um crédito de € 40, o relatório exibirá € 140.
>
> O valor originalmente calculado foi € 100, e o valor líquido após crédito seria € 60. Nenhuma dessas interpretações corresponde a € 140.

16:48. A IA parou no total que somava o crédito.

> Pensando agora, em qual cenario receberia um credito?

16:50. A IA descreveu o caso em que o crédito aparece.

> setembro foi fechado com € 0 de comissão, mas a comissao minima nao eh 29?

16:51. A IA alinhou o exemplo ao mínimo de € 29.

> desenhe, pfv?

16:52. A IA desenhou o exemplo.

> Ficou incompleto

16:54. A IA completou o desenho.

> Eu ainda nao entendi o erro

16:58. A IA reexplicou por que € 140 não servia.

> Qual sua sugestao?

16:59. A IA sugeriu mostrar os € 100 cobrados e um total de € 60.

> Faca assim

17:01. O total do ano passou a ser o valor cobrado menos os créditos gravados naquele ano.

> Deixe explicito e marcado no relatorio anual o total daquele ano sem ajustes, tbm

17:01. A coluna “Total without adjustments” ficou marcada. Ela mostra só o valor cobrado.

> Importando os dados históricos em outubro de 2026, o sistema pode criar os desembolsos de 2022 e 2023, mas não cria automaticamente todas as taxas mensais daqueles anos.

17:07. Cada run passou a fechar todo mês desde o `live_on` até o mês anterior. Outubro de 2026 cria as fees de 2022 até setembro de 2026. Outubro de 2026 fica aberto.

> comite push e abra Pr

17:09. [Pull request #28](https://github.com/rafael-pissardo/lagom/pull/28).

## Disclaimer

> Deixe um disclaimer bem claro que eu entendo que mes processado eh imutavel. Que um edge case importante eh que orders posteriores ao seu mes de fechamento nao podem alterar o mes ja fechado. Devem entrar, obrigatoriamente, como ajuste. Isso garante auditoria, politicas publicas e etc.
>
> Portanto, alterei pequenos detalhes em relacao ao fluxo e aos relatorios desses edge cases que podem variar quando comparado com o fluxo original do enunciado.

18:50. O README ganhou o disclaimer. Mês processado não muda. Pedido que chega depois entra como ajuste.

> Quero deixar mais em destaque

18:51. O aviso passou para um bloco de caution no topo.

> Adicione algumas timelines mostrando esses edge cases

18:52. O README ganhou três diagramas desses casos.

> Os diagramas estao com erro

18:54. A IA trocou o tipo de diagrama. A prévia do Rafael continuou quebrando.

> Quero linhas do tempo mais bonitas e visuais

18:58. A IA redesenhou.

> Ta quebrando ainda.

19:00. Os diagramas viraram flowchart, sem os caracteres que a prévia rejeitava.

> adicione essa foto entre o titulo do Disclaimer e a mensagem de disclaimer

19:09. A foto de stop entrou entre o título e o texto. O arquivo ficou em `docs/images/disclaimer-stop.jpg`.

> Em Settlement rules implemented, o README afirma corretamente que a aplicação fecha todos os meses anteriores ainda pendentes.
>
> Porém, em Decisions not taken e What I would improve with more time, ainda diz que o sistema fecha apenas o mês imediatamente anterior e não recupera os demais.
>
> O código atual de SettleMerchantsService já percorre todos os meses decorridos.

19:10. A IA tirou as frases velhas que ainda diziam “só o mês anterior”.

> Verique mais falhar no Readme que eu nao peguei

19:10. A frase chegou duas vezes. A IA listou quatro divergências e não editou o README por causa delas.

> Comite, push e abra PR

19:13. [Pull request #29](https://github.com/rafael-pissardo/lagom/pull/29).

## Import em stream e a referência

> Certo, agora vamos validar e processar o import por streaming, limitando a memória proporcionalmente ao tamanho do lote, não do arquivo?

19:18. A validação e a gravação do CSV passaram a ler o arquivo em pedaços. O arquivo inteiro não entra numa string só.

> O enunciado exige uma referência única alfanumérica.
>
> Como os merchants possuem referências como treutel_schumm_fadel, o resultado contém _, que não é um caractere alfanumérico.
>
> A unicidade está garantida pelo índice do banco, mas o formato não atende literalmente à especificação.
>
> Porque não usar um uuid?

19:29. A IA respondeu a partir do código e do registro do dia 1: a referência era a concatenação do merchant com a data, e o underscore tinha sido aceito naquele dia.

> o título da página do desembolso e o texto do link nos índices e na página do merchant podem ser algo mais humanizado.

19:32. O link e o título passaram a mostrar o merchant e a data, no lugar da referência crua.

> No nome do merchant coloque como nome proprio

19:51. Cada parte separada por `_` ficou com a inicial maiúscula.

> A referência gravada quero um uuid, mas acho que terei que alterar o CSV, nao?

19:52. A IA respondeu que não. O CSV não traz a referência do disbursement. Ela nasce na liquidação.

> Certo, entao quero um UUID

19:52. A referência gravada passou a ser um UUID.

> comite, merge e abra PR

19:55. [Pull request #30](https://github.com/rafael-pissardo/lagom/pull/30), mergeado.

> Specs e coverage

19:59. A suíte rodou com coverage. Dois exemplos de lista ainda esperavam a referência crua. A IA ajustou esses exemplos para o texto humanizado.

> Execute the selected diff-tab commit-and-push action.

20:29. Commit e push na branch do #30, que já estava mergeada. O `main` não recebeu esse commit.

> eu ja tinha mergeado o PR

20:42. A IA abriu o [pull request #31](https://github.com/rafael-pissardo/lagom/pull/31) a partir da `main`, com o mesmo ajuste dos specs.

> Percebi que o SecureRandom.uuid vai colocar - no reference. Vamos usar SecureRandom.hex(16) no lugar? Isso para o disbursement

21:53. A referência do disbursement passou a 32 caracteres hexadecimais, sem hífen.

## Data do desembolso e os créditos

> Em DisburseMerchantService, a data do desembolso pode ser calculada como um dia anterior ao processamento real.
>
> Exemplo: o merchant recebeu em 5 de setembro; um pedido antigo é importado no dia 10; o sistema pode criar um desembolso datado de 6 de setembro.
>
> Isso é aceitável como reconstrução histórica, mas problemático quando o campo representa a data em que o pagamento efetivamente ocorreu.
>
> Vamos distinguir claramente o backfill histórico da liquidação operacional de novos pedidos?

21:57. A IA leu o código e esperou a decisão. Não inventou uma segunda data.

> O que representa disbursed_on?
> A data em que o desembolso foi emitido/processado, não a data em que deveria ter ocorrido.
>
> Como distinguir as datas?
> Usar os campos existentes. Não adicionar marcador nem segunda data inicialmente.
>
> Dia 10 encontra pedido antigo e pedido de ontem?
> Um único disbursement, contendo ambos, para o mesmo merchant elegível.
>
> Qual data o relatório anual considera?
> disbursed_on, ou seja, o ano da emissão do desembolso.

22:00. A frase chegou duas vezes. `disbursed_on` passou a ser o dia em que o job roda. Pedido antigo e pedido de ontem do mesmo merchant entram no mesmo disbursement. O relatório anual continua no ano de `disbursed_on`. Nenhuma coluna nova.

> Em YearlyReportService, créditos são contabilizados no ano de criação do ajuste.
>
> Um crédito realizado em 2026 sobre uma mensalidade de 2022 aparece em 2026, não em 2022.
>
> Isso é defensável, e eu pedi, como visão de movimentos financeiros, mas pode diferir de um relatório de competência sobre o valor devido em cada período.
>
> Como o enunciado não define expressamente essa política, quero oferecer uma visão por competência para a tabela solicitada e manter os ajustes em uma visão separada de auditoria.

22:06. A IA tirou o crédito da tabela anual e abriu uma lista de ajustes. Nessa primeira versão, o crédito de 2026 ainda diminuía 2022.

> Na verdade nao quero que o crédito de 2026 sobre 2022 reduza 2022. Quero apresentar esses ajustes separados, mostrando o ano que foram cobrado e o ano de referencia

22:13. A tabela anual ficou só com o valor cobrado no ano da mensalidade. A lista de ajustes mostra o ano em que o crédito foi cobrado e o ano de referência da fee.

> Estamos agrupando os itens com o mesmo Ano Cobrado e mesmo ano de referencia? Se nao, agrupe

22:20. Já agrupava. A IA travou isso num spec: dois créditos com o mesmo par de anos viram uma linha, com a quantidade e a soma.

> Commite push e abra PR

22:27. [Pull request #32](https://github.com/rafael-pissardo/lagom/pull/32).

> brakman falhou

22:29. A IA tirou a interpolação de `Arel.sql` no ano do disbursement. O Brakeman passou.

> comite e push

22:32. Não havia mudança nova. O commit do Brakeman já estava no remoto.

## Ano retroativo

> Agora, quero uma forma de popular o banco com os dados do CSV de orders. Tenho um CSV de orders de 2022 e 2023 que foram pagos em dia. Pensei em fazer via seed, mas eh muita coisa. E depois com os csvs de 2026 consigo rodar normalmente.

22:37. A IA leu o import e a liquidação. Seed não entrou.

> Pensei tbm em adicionar um flag que permita um bypass e criar uma rake que pega o arquivo do bucket diretamente

22:39. A frase chegou duas vezes. A IA começou uma rake que lia o arquivo no bucket.

> E se passarmos um ano para ela considerar como current_year?

22:47. O ano passado na rake virou o limite da liquidação, no lugar de hoje.

> Se bem, que com o sistema todo vazio, apenas com merchantes e um csv de orders importado, o primeiro job diaria vai processar tudo corretamente nao?

22:50. A IA respondeu que não. O job diário junta todo o pendente num disbursement só, datado do dia em que roda.

> Blz, entao vamos focar em conseguir rodar com anos retroativos?

22:53. A IA fechou `ReplaySettlementService` e a rake com `YEAR`.

> mas preciso passar o kindo e o csv?

22:55. A IA respondeu que a rake daquele momento exigia os dois, e que o replay sozinho já dava para chamar o service.

> vou importar o csv normal. Quero a rake so pra chamar o service

22:55. A rake do bucket saiu. Ficou `bin/rails lagom:replay_year YEAR=2023`, depois do import pela tela.

> Posso ter 2022 e 2023 no mesmo csv, certo?

22:57. A IA confirmou. Com `YEAR=2023`, os dois anos são pagos no dia em que o job teria rodado. `YEAR=2022` deixaria 2023 pendente.

> comite push abra PR

22:58. [Pull request #33](https://github.com/rafael-pissardo/lagom/pull/33).

## O registro

> Faca a documentacao do quarto dia, igual fez aos demais. Comite, push e abra o PR

22 out 2026, 08:56. Este arquivo. O README aponta para ele junto dos registros dos dias 1, 2 e 3.

# ETS Snapshot Bundles

Versão de desenvolvimento **0.1.0** — biblioteca Elixir original, sem dependências externas, da [Lofrano Tecnologia](https://lofranotecnologia.com.br).

Um GenServer sem nome é dono de tabelas ETS protegidas e imutáveis. Cada leitor adquire uma concessão vinculada ao seu PID para consultar várias chaves da mesma geração. A publicação substitui o bundle completo atomicamente em relação às operações suportadas. Monitores liberam os pins de leitores encerrados.

[English](README.md) · [Contrato preciso](docs/contract.md) · [Projeto](docs/design.md)

## Instalação, testes e demonstração

Requer Elixir 1.18 ou mais recente com OTP compatível. A matriz de CI usa as imagens oficiais `elixir:1.18` e `elixir:1.20.5`. Não precisa de Hex, banco de dados, modelo, API, credenciais ou acesso à rede para compilar e executar.

No diretório do projeto:

```sh
mix compile
mix test --seed 0
mix run demo/demo.exs
```

Em uma aplicação local, adicione uma dependência Mix por caminho:

```elixir
{:ets_snapshot_bundles, path: "../ets-snapshot-bundles"}
```

A demonstração usa somente dados sintéticos e lança uma exceção se uma verificação falhar. Linhas estáveis da saída:

```text
PASS: 14 checks; coherent generations, pin-limit rejection and retry.
{"status":"ok","checks":14,"current_generation":3,"retained_tables":1}
```

Também são impressas as versões ativas de Elixir e OTP. O registro do digest da imagem e do runtime é explicado em [runtime notes](docs/runtime.md).

## Exemplo

```elixir
alias EtsSnapshotBundles, as: Bundles

{:ok, index} = Bundles.start_link(%{retired_limit: 1})
{:ok, 1} = Bundles.publish(index, [{"a", "antigo-a"}, {"b", "antigo-b"}])
{:ok, lease} = Bundles.acquire(index)
{:ok, 2} = Bundles.publish(index, [{"a", "novo-a"}, {"b", "novo-b"}],
  %{expected_generation: 1})
{:ok, "antigo-a"} = Bundles.lookup(lease, "a")
{:ok, "antigo-b"} = Bundles.lookup(lease, "b")
:ok = Bundles.release(lease)
{:error, :stale_snapshot} = Bundles.lookup(lease, "a")
{:ok, stats} = Bundles.inspect(index)
1 = stats.table_count
:ok = Bundles.close(index)
```

Adquira, use e libere a concessão no **mesmo processo**. Um `try/after` permite liberação explícita mesmo após exceções. A morte do leitor também libera seus pins. `start_link/1` devolve um handle de instância, não o resultado usual com PID; não é diretamente uma especificação de filho para Supervisor.

```elixir
{:ok, lease} = Bundles.acquire(index, %{timeout: 1000})
try do
  Bundles.lookup(lease, "rota")
after
  Bundles.release(lease)
end
```

Padrões: 4.096 entradas, 1 MiB lógico de chaves mais valores por bundle, 128 concessões, duas gerações antigas fixadas e 64 vagas de admissão. Chaves são binários de até 128 bytes; valores, até 4 KiB. A entrada deve ser uma lista própria e limitada de pares binários. Chaves duplicadas rejeitam a publicação inteira. Enumerables arbitrários não são consumidos.

## Decisões e limitações

A nova tabela é construída completamente antes da troca da geração atual. Intermediários monitorados e um contador atômico limitam os pedidos antes do envio ao servidor. Timeout não devolve uma vaga enquanto o trabalho continua enfileirado. Uma aquisição com timeout é descartada ou revertida, mesmo quando o leitor continua vivo.

Nesta versão, todas as operações, inclusive consultas, passam pelo dono do índice. Essa escolha simplifica a verificação da propriedade e da recuperação das tabelas. Não há alegações de desempenho.

Os limites cobrem pedidos suportados em andamento e payload lógico, não toda a memória da VM, cópias de mensagens, armazenamento subjacente de binários, atrasos do escalonador ou mensagens BEAM maliciosas. Cada chamada cria brevemente um intermediário, inclusive quando retorna `busy`. Leitores duradouros podem bloquear publicações. ETS protegido não é uma fronteira de confidencialidade entre códigos confiáveis da mesma VM.

Não há persistência, replicação, consenso distribuído, expiração de concessões, isolamento de tenants, merge ou recuperação transparente. Reiniciar o dono cria uma instância vazia na geração 0; handles antigos retornam `unavailable`. Timeout de publicação pode ocorrer depois do commit: inspecione a geração e use compare-and-publish para reconciliar. Timeout de pedido não é expiração de concessão.

Licença MIT, copyright 2026 Lofrano Tecnologia. Contato geral: [site oficial](https://lofranotecnologia.com.br). Relatos de segurança: [SECURITY.md](SECURITY.md).

# ReStore

A distributed key-value store for small, simple datasets.

It's still in development, so it's not on Hex yet.

# Usage

```elixir
# lib/my_app/my_fancy_store.ex
defmodule MyApp.MyFancyStore do
  use ReStore, pubsub: MyApp.PubSub, topic: "__my_fancy_store__"

  def handle_puts(metas) do
    # optional; handle new metas here
  end

  def handle_deletes(metas) do
    # optional; handle gone metas here
  end
end
```

Add it to your supervision tree

```elixir
# lib/my_app/application.ex
defmodule MyApp.Application do
  use Application

  def start(_type, _args) do
    children = [
      # ...other children...
      MyApp.MyFancyStore
    ]

    # ...start children...
  end
end
```

## Installation

The package can be installed by adding `re_store` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:re_store, github: "schrockwell/re_store"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/re_store>.

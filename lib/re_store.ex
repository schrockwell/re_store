defmodule ReStore do
  @callback handle_puts(metas :: list) :: any
  @callback handle_deletes(metas :: list) :: any

  defmacro __using__(opts) do
    pubsub = Keyword.fetch!(opts, :pubsub)
    topic = Keyword.fetch!(opts, :topic)

    quote do
      @behaviour ReStore

      def __pubsub__, do: unquote(pubsub)
      def __topic__, do: unquote(topic)
      def __table__, do: __MODULE__

      def handle_puts(metas), do: :ok
      def handle_deletes(metas), do: :ok

      defoverridable handle_puts: 1, handle_deletes: 1

      def child_spec(_) do
        %{
          id: __MODULE__,
          start: {ReStore.Server, :start_link, [__MODULE__]}
        }
      end
    end
  end

  def register(module, pid, meta) do
    GenServer.call(module, {:register, [{pid, meta}]})
  end

  def put(module, pid, meta) do
    GenServer.call(module, {:put, [{pid, meta}]})
  end

  def merge(module, pid, changes) when is_map(changes) do
    GenServer.call(module, {:merge, [{pid, changes}]})
  end

  def list(module) do
    module.__table__()
    |> :ets.tab2list()
    |> Enum.map(fn {_pid, _owner, meta} -> meta end)
  end
end

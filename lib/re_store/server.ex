defmodule ReStore.Server do
  use GenServer

  alias Phoenix.PubSub

  def start_link(module) do
    GenServer.start_link(__MODULE__, module, name: module)
  end

  @impl true
  def init(module) do
    pubsub = module.__pubsub__()
    topic = module.__topic__()
    table_name = module.__table__()

    table = :ets.new(table_name, [:named_table, read_concurrency: true])

    PubSub.subscribe(pubsub, topic)
    PubSub.broadcast_from!(pubsub, self(), topic, {:hello, self()})

    {:ok,
     %{
       module: module,
       peers: MapSet.new(),
       pubsub: pubsub,
       table: table,
       topic: topic
     }}
  end

  @impl true
  def handle_call({:register, entries}, _, state) do
    PubSub.broadcast_from!(state.pubsub, self(), state.topic, {:register, self(), entries})
    {:reply, :ok, do_register(state, self(), entries)}
  end

  def handle_call({:put, entries}, _, state) do
    PubSub.broadcast_from!(state.pubsub, self(), state.topic, {:put, entries})
    {:reply, :ok, do_put(state, entries)}
  end

  def handle_call({:merge, entries}, _, state) do
    PubSub.broadcast_from!(state.pubsub, self(), state.topic, {:merge, entries})
    {:reply, :ok, do_merge(state, entries)}
  end

  @impl true
  def handle_info({:hello, pid}, state) do
    send(pid, {:register, self(), local_entries(state.table, self())})
    {:noreply, state}
  end

  def handle_info({:register, owner, entries}, state) do
    {:noreply, do_register(state, owner, entries)}
  end

  def handle_info({:put, entries}, state) do
    {:noreply, do_put(state, entries)}
  end

  def handle_info({:merge, entries}, state) do
    {:noreply, do_merge(state, entries)}
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    if MapSet.member?(state.peers, pid) do
      # A peer ReStore server owner went away
      old_objects = :ets.match_object(state.table, {:_, pid, :_})
      :ets.match_delete(state.table, {:_, pid, :_})

      old_metas = Enum.map(old_objects, fn {_, _, meta} -> meta end)
      state.module.handle_deletes(old_metas)

      {:noreply, %{state | peers: MapSet.delete(state.peers, pid)}}
    else
      # A monitored state process went away
      old_object = :ets.lookup(state.table, pid)
      :ets.delete(state.table, pid)

      with [{_, _, old_meta}] <- old_object do
        state.module.handle_deletes([old_meta])
      end

      {:noreply, state}
    end
  end

  defp do_register(state, owner, entries) do
    # Monitor the owner if we haven't already
    state =
      if MapSet.member?(state.peers, owner) do
        state
      else
        Process.monitor(owner)
        state = %{state | peers: MapSet.put(state.peers, owner)}
        state
      end

    # Insert the objects into the table
    for {pid, meta} <- entries do
      Process.monitor(pid)

      :ets.insert(state.table, {pid, owner, meta})
    end

    metas = Enum.map(entries, fn {_, meta} -> meta end)
    state.module.handle_puts(metas)

    state
  end

  defp do_put(state, entries) do
    new_metas =
      Enum.flat_map(entries, fn {pid, meta} ->
        case :ets.lookup(state.table, pid) do
          [] ->
            []

          [{_pid, owner, _meta}] ->
            :ets.insert(state.table, {pid, owner, meta})
            [meta]
        end
      end)

    state.module.handle_puts(new_metas)

    state
  end

  defp do_merge(state, entries) do
    puts =
      Enum.flat_map(entries, fn {pid, changes} ->
        case :ets.lookup(state.table, pid) do
          [] ->
            []

          [{_pid, owner, meta}] ->
            new_meta = Map.merge(meta, changes)
            :ets.insert(state.table, {pid, owner, new_meta})
            [new_meta]
        end
      end)

    state.module.handle_puts(puts)

    state
  end

  defp local_entries(table, owner) do
    table
    |> :ets.tab2list()
    |> Enum.filter(fn {_, owner_pid, _} -> owner_pid == owner end)
    |> Enum.map(fn {pid, _, meta} -> {pid, meta} end)
  end
end

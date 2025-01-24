defmodule ReStoreTest do
  use ExUnit.Case
  # doctest ReStore

  alias Phoenix.PubSub

  @pubsub ReStoreTest.PubSub

  defmodule TestStore1 do
    use ReStore, pubsub: ReStoreTest.PubSub, topic: "test"

    def handle_puts(metas) do
      PubSub.broadcast(ReStoreTest.PubSub, "test_store_1", {:handle_puts, metas})
    end

    def handle_deletes(metas) do
      PubSub.broadcast(ReStoreTest.PubSub, "test_store_1", {:handle_deletes, metas})
    end
  end

  defmodule TestStore2 do
    use ReStore, pubsub: ReStoreTest.PubSub, topic: "test"

    def handle_puts(metas) do
      PubSub.broadcast(ReStoreTest.PubSub, "test_store_2", {:handle_puts, metas})
    end

    def handle_deletes(metas) do
      PubSub.broadcast(ReStoreTest.PubSub, "test_store_2", {:handle_deletes, metas})
    end
  end

  setup_all do
    start_supervised({PubSub, name: @pubsub})
    :ok
  end

  test "can register and list with a single instance" do
    # GIVEN
    start_supervised!(TestStore1)

    # WHEN
    meta = %{name: "test"}
    TestStore1.register(self(), meta)

    # THEN
    assert TestStore1.list() == [meta]
  end

  test "can register and list across instances" do
    # GIVEN
    start_supervised!(TestStore1)
    start_supervised!(TestStore2)

    # WHEN
    meta = %{name: "test"}
    TestStore1.register(self(), meta)
    flush(TestStore2)

    # THEN
    assert TestStore2.list() == [meta]
  end

  test "can put across instances" do
    # GIVEN
    start_supervised!(TestStore1)
    start_supervised!(TestStore2)

    meta1 = %{name: "test1"}
    TestStore1.register(self(), meta1)

    # WHEN
    meta2 = %{name: "test2"}
    TestStore1.put(self(), meta2)
    flush(TestStore2)

    # THEN
    assert TestStore2.list() == [meta2]
  end

  test "can merge across instances" do
    # GIVEN
    start_supervised!(TestStore1)
    start_supervised!(TestStore2)

    meta = %{name: "test1", id: 123}
    TestStore1.register(self(), meta)

    # WHEN
    changes = %{name: "test2"}
    TestStore1.merge(self(), changes)
    flush(TestStore2)

    # THEN
    assert TestStore2.list() == [Map.merge(meta, changes)]
  end

  test "removes local entries when the process dies" do
    # GIVEN
    start_supervised!(TestStore1)

    task = Task.async(fn -> Process.sleep(1000) end)

    TestStore1.register(task.pid, %{name: "test"})

    # WHEN
    Task.shutdown(task, :brutal_kill)
    flush(TestStore1)

    # THEN
    assert TestStore1.list() == []
  end

  test "removes remote entries when the process dies" do
    # GIVEN
    start_supervised!(TestStore1)
    start_supervised!(TestStore2)

    task = Task.async(fn -> Process.sleep(1000) end)

    TestStore1.register(task.pid, %{name: "test"})

    # WHEN
    Task.shutdown(task, :brutal_kill)
    assert_down(task.pid)
    flush(TestStore2)

    # THEN
    assert TestStore2.list() == []
  end

  test "removes remote entries when the peer ReStore server dies" do
    # GIVEN
    store1 = start_supervised!(TestStore1)
    start_supervised!(TestStore2)

    TestStore1.register(self(), %{name: "test"})

    # WHEN
    Process.exit(store1, :kill)
    assert_down(store1)
    flush(TestStore2)

    # THEN
    assert TestStore2.list() == []
  end

  test "new instance gets entries from existing instances" do
    # GIVEN
    start_supervised!(TestStore1)

    meta = %{name: "test"}
    TestStore1.register(self(), meta)

    # WHEN
    start_supervised!(TestStore2)
    flush(TestStore1)
    flush(TestStore2)

    # THEN
    assert TestStore2.list() == [meta]
  end

  test "handle_puts/1 is called when a new entry is registered" do
    # GIVEN
    start_supervised!(TestStore1)
    start_supervised!(TestStore2)
    PubSub.subscribe(@pubsub, "test_store_1")
    PubSub.subscribe(@pubsub, "test_store_2")

    meta = %{name: "test"}

    # WHEN
    TestStore1.register(self(), meta)

    # THEN
    assert_receive {:handle_puts, [^meta]}
    assert_receive {:handle_puts, [^meta]}
  end

  test "handle_puts/1 is called when an entry is updated" do
    # GIVEN
    start_supervised!(TestStore1)
    start_supervised!(TestStore2)
    PubSub.subscribe(@pubsub, "test_store_1")
    PubSub.subscribe(@pubsub, "test_store_2")

    meta1 = %{name: "test1"}
    meta2 = %{name: "test2"}

    # WHEN
    TestStore1.register(self(), meta1)
    TestStore1.put(self(), meta2)

    # THEN
    assert_receive {:handle_puts, [^meta1]}
    assert_receive {:handle_puts, [^meta1]}
    assert_receive {:handle_puts, [^meta2]}
    assert_receive {:handle_puts, [^meta2]}
  end

  test "handle_deletes/1 is called when a process dies" do
    # GIVEN
    start_supervised!(TestStore1)
    start_supervised!(TestStore2)
    PubSub.subscribe(@pubsub, "test_store_1")
    PubSub.subscribe(@pubsub, "test_store_2")

    meta = %{name: "test"}
    task = Task.async(fn -> Process.sleep(1000) end)

    # WHEN
    TestStore1.register(task.pid, meta)
    Task.shutdown(task, :brutal_kill)

    # THEN
    assert_receive {:handle_deletes, [^meta]}
    assert_receive {:handle_deletes, [^meta]}
  end

  test "handle_deletes/1 is called when a store process dies" do
    # GIVEN
    store1 = start_supervised!(TestStore1)
    start_supervised!(TestStore2)
    PubSub.subscribe(@pubsub, "test_store_2")

    meta1 = %{name: "test1"}
    task1 = Task.async(fn -> Process.sleep(1000) end)

    meta2 = %{name: "test2"}
    task2 = Task.async(fn -> Process.sleep(1000) end)

    # WHEN
    TestStore1.register(task1.pid, meta1)
    TestStore1.register(task2.pid, meta2)
    Process.exit(store1, :kill)
    assert_down(store1)

    # THEN
    assert_receive {:handle_puts, [^meta1]}
    assert_receive {:handle_puts, [^meta2]}
    assert_receive {:handle_deletes, deleted_metas}

    assert Enum.sort(deleted_metas) == Enum.sort([meta1, meta2])
  end

  defp flush(server), do: :sys.get_state(server)

  defp assert_down(pid) do
    Process.monitor(pid)
    assert_receive {:DOWN, _, :process, ^pid, _}
  end
end

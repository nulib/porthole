defmodule Porthole do
  require Logger

  @default_line_length 512
  @default_timeout 30_000

  @callback handle_message(action :: atom(), payload :: binary()) ::
              :continue | {:ok, any()} | {:error, any()}

  defmacro __using__(opts) do
    command = Keyword.get(opts, :command)
    if is_nil(command), do: raise(ArgumentError, message: ":command option is required")

    timeout = Keyword.get(opts, :timeout, @default_timeout)

    opts =
      [
        {:env, Keyword.get(opts, :env, nil)},
        {:args, Keyword.get(opts, :args, nil)},
        {:line, Keyword.get(opts, :line, @default_line_length)},
        :binary,
        :exit_status
      ]
      |> Enum.reject(fn
        {_, v} -> is_nil(v)
        _ -> false
      end)

    quote bind_quoted: [cmd: command, opts: opts, timeout: timeout] do
      @behaviour Porthole
      require Logger

      def command(payload),
        do: Porthole.command(__MODULE__, unquote(cmd), unquote(opts), payload, unquote(timeout))

      def handle_message(:ok, result), do: {:ok, result}
      def handle_message(:debug, message), do: Porthole.log(:debug, message)
      def handle_message(:info, message), do: Porthole.log(:info, message)
      def handle_message(:warn, message), do: Porthole.log(:warn, message)
      def handle_message(:error, message), do: Porthole.log(:error, message)

      def handle_message(:fatal, message),
        do: Porthole.log(:error, message, {:error, message})

      def handle_message(:default, message),
        do: Porthole.log(:warn, "Malformed payload: #{message}")

      defoverridable(handle_message: 2)
    end
  end

  def command(caller, cmd, opts, payload, timeout) do
    with port <- find_or_create_port(cmd, opts) do
      send(port, {self(), {:command, "#{payload}\n"}})
      handle_output(caller, port, timeout)
    end
  end

  def log(level, message, return_value \\ :continue) do
    Logger.log(level, message)
    return_value
  end

  defp find_or_create_port(cmd, opts) do
    pyramid_port? = fn p ->
      case Port.info(p) do
        nil -> false
        port -> cmd == port |> Keyword.get(:name) |> to_string()
      end
    end

    case Enum.find(Port.list(), pyramid_port?) do
      nil ->
        with exe <- cmd |> find_command() do
          Logger.info("Spawning #{exe} in a new port")
          Process.flag(:trap_exit, true)
          port = Port.open({:spawn_executable, exe}, opts)
          Port.monitor(port)
          port
        end

      port ->
        Logger.debug("Using port #{inspect(port)} for #{cmd}")
        port
    end
  end

  defp find_command(cmd) do
    cond do
      File.exists?(cmd) -> cmd
      v = System.find_executable(cmd) -> v
      true -> raise ArgumentError, "Command not found: #{cmd}"
    end
  end

  defp handle_message(caller, message) do
    case(message |> String.split("|", parts: 2)) do
      [action, payload] ->
        caller.handle_message(String.to_atom(action), payload)

      _ ->
        caller.handle_message(:default, message)
    end
  end

  defp handle_output(caller, port, timeout, buffer \\ "") do
    receive do
      {^port, {:data, {:noeol, data}}} ->
        handle_output(caller, port, timeout, buffer <> data)

      {^port, {:data, {:eol, data}}} ->
        case handle_message(caller, buffer <> data) do
          :continue -> handle_output(caller, port, timeout)
          other -> other
        end

      {^port, {:exit_status, status}} ->
        Logger.error("exit status: #{status}")
        {:error, {:exit_status, status}}
    after
      timeout ->
        Logger.error("No response after #{timeout}ms")
        {:error, :timeout}
    end
  end
end

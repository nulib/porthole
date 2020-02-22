defmodule PortholeTest do
  use ExUnit.Case
  import ExUnit.CaptureLog

  @default_log_output """
  [info]  Spawning ./test/scripts/default.sh in a new port
  [info]  first info message
  [debug] first debug message
  [info]  second info message
  [warn]  first warning message
  [error] first error message
  [warn]  second warning message
  """

  describe "default implementation" do
    defmodule DefaultPorthole do
      use Porthole, command: "./test/scripts/default.sh"
    end

    test "logs info and continues" do
      assert @default_log_output ==
               capture_log(fn -> assert DefaultPorthole.command("run") == {:ok, "done"} end)
    end
  end

  describe "fatal error" do
    defmodule FatalPorthole do
      use Porthole, command: "./test/scripts/fatal.sh"
    end

    test "logs and halts on fatal error" do
      assert capture_log(fn -> assert FatalPorthole.command("run") == {:error, "dead"} end)
             |> String.ends_with?("[warn]  about to die\n[error] dead\n")
    end
  end

  describe "custom implementation" do
    defmodule CustomPorthole do
      use Porthole, command: "./test/scripts/custom.sh"

      def handle_message(:warn, _), do: {:error, "overridden warn"}
      def handle_message(:custom, _), do: {:ok, "custom action"}
      def handle_message(action, payload), do: super(action, payload)
    end

    test "handle overrides and custom actions" do
      with log <-
             capture_log(fn ->
               assert CustomPorthole.command("run") == {:error, "overridden warn"}
             end) do
        assert log |> String.contains?("[info]  normal information")
        refute log |> String.contains?("[warn]  overridden warning")
      end

      capture_log(fn -> assert CustomPorthole.command("run") == {:ok, "custom action"} end)
    end
  end

  describe "buffering" do
    defmodule BufferPorthole do
      use Porthole, command: "./test/scripts/default.sh", line: 16
    end

    test "handles chunked messages" do
      assert @default_log_output ==
               capture_log(fn -> assert BufferPorthole.command("run") == {:ok, "done"} end)
    end
  end

  describe "reuse existing port" do
    defmodule ReusePorthole do
      use Porthole, command: "./test/scripts/reuse.sh"
    end

    test "reuses an existing port" do
      assert capture_log(fn ->
               assert ReusePorthole.command("first run") == {:ok, "first run"}
             end) =~ ~r"Spawning ./test/scripts/reuse.sh in a new port"

      assert capture_log(fn ->
               assert ReusePorthole.command("second run") == {:ok, "second run"}
             end) =~ ~r"Using port #Port<\d+.\d+> for ./test/scripts/reuse.sh"
    end
  end

  describe "malformed message" do
    defmodule MalformedPorthole do
      use Porthole, command: "./test/scripts/malformed.sh"
    end

    test "gracefully handles malformed responses" do
      assert capture_log(fn ->
               assert MalformedPorthole.command("run") == {:ok, ""}
             end)
             |> String.contains?("Malformed payload: this message doesn't follow the protocol")
    end
  end

  describe "unexpected exit" do
    defmodule ExitPorthole do
      use Porthole, command: "sh", args: ["-c", "read; exit 109"]
    end

    test "gracefully handles termination of the spawned process" do
      assert capture_log(fn ->
               assert ExitPorthole.command("run") == {:error, {:exit_status, 109}}
             end)
             |> String.contains?("[error] exit status: 109")
    end
  end

  describe "timeout" do
    defmodule TimeoutPorthole do
      use Porthole, command: "sleep", args: ["5"], timeout: 10
    end

    test "times out" do
      assert capture_log(fn ->
               assert TimeoutPorthole.command("run") == {:error, :timeout}
             end)
             |> String.contains?("No response after 10ms")
    end
  end

  describe "no command" do
    test "macro complains when there's no command" do
      assert_raise(
        ArgumentError,
        ":command option is required",
        fn ->
          defmodule NoCommandPorthole do
            use Porthole
          end
        end
      )
    end
  end

  describe "bad command" do
    defmodule BadCommandPorthole do
      use Porthole, command: "abutheuiwuhfew"
    end

    test "raises ArgumentError" do
      assert "abutheuiwuhfew" |> System.find_executable() |> is_nil()

      capture_log(fn ->
        assert_raise(
          ArgumentError,
          "Command not found: abutheuiwuhfew",
          fn -> BadCommandPorthole.command("ok|") end
        )
      end)
    end
  end

  describe "unrunnable command" do
    defmodule UnrunnableCommandPorthole do
      use Porthole, command: "./test/scripts/unrunnable.sh"
    end

    test "raises ArgumentError" do
      capture_log(fn ->
        assert_raise(
          ErlangError,
          "Erlang error: :eacces",
          fn -> UnrunnableCommandPorthole.command("ok|") end
        )
      end)
    end
  end
end

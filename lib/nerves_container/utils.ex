defmodule NervesContainer.Utils do
  @moduledoc false

  @doc false
  @spec shell_info(String.t(), String.t()) :: :ok
  def shell_info(header, text \\ "") do
    Mix.Nerves.IO.shell_info(header, text, Container)
  end
end

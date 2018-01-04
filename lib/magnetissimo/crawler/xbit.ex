defmodule Magnetissimo.Crawler.XBit do
  @moduledoc """
  Torrent parser for xBit in charge of parsing the API
  """

  use GenServer
  require Logger
  require Poison
  import Magnetissimo.Crawler.Helper
  alias Magnetissimo.Torrent

  def initial_queue do
    url = "https://xbit.pw/api"
    case download(url) do
      {:ok, body} ->
        body
        |> Poison.decode
        |> case do
          {:ok, data} ->
            data["dht_results"]
          {:error, msg} ->
            Logger.error "[xBit] #{inspect msg}"
            []
          end
      {:error, :wrong_headers} ->
        Logger.error "[xBit] Wrong headers in the HTTP Response!"
        []
    end
  end

  def start_link(_) do
    queue = initial_queue()
    GenServer.start_link(__MODULE__, queue, name: __MODULE__)
  end

  def init(queue) do
    Logger.info IO.ANSI.magenta <> "Starting xBit crawler" <> IO.ANSI.reset
    schedule_start()
    {:ok, queue}
  end

  def schedule_start() do
    wait = :rand.uniform(8) * 1000 # [1,8] seconds
    Process.send_after(self(), :work, wait)
  end

  def schedule_work() do
    wait = 1800000 # 30mn
    Logger.info("[xBit] Finished crawling the RSS feed, waiting 30 minutes…")
    Process.send_after(self(), :work, wait)
  end

  def handle_info(:work, queue) do
    queue
    |> Enum.each(&(process(&1)))
    schedule_work()
    {:noreply, initial_queue()}
  end

  def process(item) do
    case item["NAME"] do
      nil -> nil # xBit includes an empty entry at the end of dht_results
      _ ->
        item
        |> torrent_information
        |> Torrent.save_torrent()
      end
  end

  defp fix_size(size) do
    {number_part, unit_part} = Float.parse size
    fixed_size = case String.trim(unit_part) do
      "PB" ->
        number_part * :math.pow(1024, 5)
      "TB" ->
        number_part * :math.pow(1024, 4)
      "GB" ->
        number_part * :math.pow(1024, 3)
      "MB" ->
        number_part * :math.pow(1024, 2)
      "kB" ->
        number_part * :math.pow(1024, 1)
      "B" ->
        number_part
    end

    fixed_size
      |> round
      |> Integer.to_string
  end

  def torrent_information(item) do
    %{
      name: item["NAME"],
      magnet: item["MAGNET"],
      size: (item["SIZE"] |> fix_size),
      website_source: "xbit",
      seeders:  0,
      leechers: 0,
      outbound_url: "https://xbit.pw/?id=#{item["ID"]}"
    }
  end
end

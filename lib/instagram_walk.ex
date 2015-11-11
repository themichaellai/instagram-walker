defmodule InstagramWalk do
  @client_id ""
  @access_token ""

  def url_builder(path) do
    "https://api.instagram.com/#{Enum.join(path, "/")}"
  end

  def ig_raw_request(full_path) do
    try do
      Instagram.get(full_path)
    rescue
      HTTPotion.HTTPError ->
        time = round(Float.floor(:random.uniform * 4000))
        IO.puts("#{inspect self()} Sleeping #{time}...")
        :timer.sleep(time)
        ig_raw_request(full_path)
    end
  end

  def ig_request(path, acc \\ [], opts \\ %{}) do
    query_dict = %{
      cursor: Map.get(opts, :cursor, ""),
      max_id: Map.get(opts, :next_max_id, ""),
      access_token: @access_token,
      count: Map.get(opts, :count, ""),
    }
    res = ig_raw_request("#{path}?#{URI.encode_query(query_dict)}")

    try do
      body = res.body |> to_string |> Poison.Parser.parse!
      res = body["data"]
      #|> Enum.map(fn(p) -> Map.take(p, ["full_name", "username", "id"]) end)
      #IO.puts "max: #{Map.get(opts, :max, -1)} / #{length(res)} + #{length(acc)}"
      if Map.has_key?(body, "pagination") do
        case body["pagination"] do
          %{"next_cursor" => next_cursor} ->
            new_opts = Map.merge(opts, %{cursor: next_cursor})
            ig_request(path, acc ++ res, new_opts)
          %{"next_max_id" => next_max_id} ->
            new_opts = Map.merge(opts, %{next_max_id: next_max_id})
            ig_request(path, acc ++ res, new_opts)
          _ -> {:success, acc ++ res}
        end
        #if Map.has_key?(opts, :max) and length(acc) + length(res) > opts[:max] do
        #  {:success, acc ++ res}
        #else
        #  new_opts = Map.merge(opts, %{cursor: body["pagination"]["next_cursor"]})
        #  ig_request(path, acc ++ res, new_opts)
        #end
      else
        {:success, acc ++ res}
      end
    rescue
      Poison.SyntaxError -> {:failure, {res.status_code, res.body}}
    end
  end

  def get_media() do
    receive do
      {pid, username} ->
        send(pid, {:media, ig_request("users/#{username}/media/recent", [], %{max: 100})})
    after
      1000 -> IO.puts "get_following timeout"
    end
  end

  def get_media_likes(id) do
    case ig_request("media/#{id}/likes", [], %{count: 200}) do
      {:success, likes} -> likes |> (Enum.map fn(m) -> m["username"] end)
      _ -> []
    end
  end

  def get_following() do
    receive do
      {pid, username} ->
        send(pid, {:following, ig_request("users/#{username}/follows/")})
    after
      1000 -> IO.puts "get_following timeout"
    end
  end

  def get_followers() do
    receive do
      {pid, username} ->
        send(pid, {:followers, ig_request("users/#{username}/followed-by/")})
    end
  end

  def username_map(user_list) do
    user_list
    |> Enum.reduce(Map.new, fn(p, m) -> Map.put(m, p["username"], Map.drop(p, ["username"])) end)
  end

  def map_keys_to_set(map) do
    map
    |> Map.keys
    |> Enum.reduce(HashSet.new, fn(k, s) -> HashSet.put(s, k) end)
  end

  def main(args) do
    username = List.first(args)
    #IO.puts("https://instagram.com/oauth/authorize/?client_id=#{@client_id}&redirect_uri=http://localhost&response_type=token")
    media_pid = spawn_link(fn -> get_media end)
    send(media_pid, {self(), (if username == nil, do: "self", else: username)})

    receive do
      {:media, {:success, res}} ->
        media = res |> Enum.map(fn(p) -> p["id"] end)
      {:media, {:failure, {status, res}}} ->
        IO.puts res
        IO.puts status
        raise "Failed media request"
    after
      10000 -> raise "media timeout"
    end
    #IO.puts "#{inspect(media)} #{length media}"

    likes = media
            |> Enum.map(fn(m_id) -> Task.async(fn -> m_id |> get_media_likes end) end)
            |> Enum.map(&Task.await/1)
    #IO.puts inspect(likes)
    counts = likes
              |> List.flatten
              |> Enum.reduce(%{}, fn(p, map) -> Map.put(map, p, Map.get(map, p, 0) + 1) end)
              |> Map.to_list
              |> List.keysort(1)
              |> Enum.reverse
    IO.puts "COUNTS"
    counts_str = counts
                  |> Enum.map(fn({p, count}) -> "#{p}: #{count}" end)
                  |> Enum.join("\n")
    IO.puts counts_str


    #following_pid = spawn_link(fn -> get_following end)
    #send(following_pid, {self(), (if username == nil, do: "self", else: username)})
    #followers_pid = spawn_link(fn -> get_followers end)
    #send(followers_pid, {self(), (if username == nil, do: "self", else: username)})
    #receive do
    #  {:followers, {:success, res}} ->
    #    followers = res
    #  {:followers, {:failure, {status, res}}} ->
    #    IO.puts res
    #    IO.puts status
    #    raise "Failed followers request"
    #after
    #  10000 -> raise "followers timeout"
    #end
    #receive do
    #  {:following, {:success, res}} ->
    #    following = res
    #  {:following, {:failure, {status, res}}} ->
    #    IO.puts res
    #    IO.puts status
    #    raise "Failed following request"
    #after
    #  10000 -> raise "following timeout"
    #end

    #IO.puts ''
    #IO.puts "FOLLOWING #{length following}"
    #names = following
    #        |> (Enum.map fn(p) -> p["username"] end)
    #        |> Enum.join "\n"
    #IO.puts names
    #IO.puts ''
    #IO.puts "FOLLOWERS #{length followers}"
    #names = followers
    #        |> (Enum.map fn(p) -> p["username"] end)
    #        |> Enum.join "\n"
    #IO.puts names

    #following_map = username_map(following)
    #followers_map = username_map(followers)

    #intersect = HashSet.intersection(map_keys_to_set(followers_map), map_keys_to_set(following_map))
    #IO.puts ''
    #IO.puts "INTERSECTION #{HashSet.size(intersect)}"
    #IO.puts intersect |> (Enum.map fn p -> "#{p} #{Map.get(following_map, p)["id"]}" end)|> Enum.join "\n"
  end
end

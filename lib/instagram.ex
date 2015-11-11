defmodule Instagram do
  use HTTPotion.Base

  def process_url(url) do
    "https://api.instagram.com/v1/" <> url
  end
end

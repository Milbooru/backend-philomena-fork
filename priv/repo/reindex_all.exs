alias Philomena.{Repo, Images.Image}

ids = Repo.all(Image) |> Enum.map(& &1.id)
IO.puts("Directly reindexing #{length(ids)} images: #{inspect(ids)}")
Philomena.IndexWorker.perform("Images", "id", ids)
IO.puts("Done")

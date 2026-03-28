defmodule Philomena.Images.TagValidator do
  alias Philomena.Config
  import Ecto.Changeset

  def validate_tags(changeset) do
    tags = changeset |> get_field(:tags)

    changeset
    |> validate_tag_input(tags)
    |> put_change(:ratings_changed, false)
  end

  defp validate_tag_input(changeset, tags) do
    tag_set = extract_names(tags)

    changeset
    |> validate_number_of_tags(tag_set, 1)
    |> validate_bad_words(tag_set)
  end

  defp validate_number_of_tags(changeset, tag_set, num) do
    if MapSet.size(tag_set) < num do
      add_error(changeset, :tag_input, "must contain at least #{num} tags")
    else
      changeset
    end
  end

  def validate_bad_words(changeset, tag_set) do
    bad_words = MapSet.new(Config.get(:tag)["blacklist"])
    intersection = MapSet.intersection(tag_set, bad_words)

    if MapSet.size(intersection) > 0 do
      Enum.reduce(
        intersection,
        changeset,
        &add_error(&2, :tag_input, "contains forbidden tag `#{&1}'")
      )
    else
      changeset
    end
  end

  defp extract_names(tags) do
    tags
    |> Enum.map(& &1.name)
    |> MapSet.new()
  end

end

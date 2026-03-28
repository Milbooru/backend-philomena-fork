defmodule Philomena.Repo.Migrations.AddImageAnnotations do
  use Ecto.Migration

  def up do
    alter table(:images) do
      add :annotations, {:array, :map}, default: []
    end
  end
end

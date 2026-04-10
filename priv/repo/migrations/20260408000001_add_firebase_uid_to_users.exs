defmodule Philomena.Repo.Migrations.AddFirebaseUidToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :firebase_uid, :string, null: true
    end

    create unique_index(:users, [:firebase_uid])
  end
end

Sequel.migration do
  up do
    create_table(:experiments) do
      primary_key :id
      DateTime :created_at, null: false
      DateTime :updated_at, null: false
      String :name, null: false
      index :name, unique: true
    end
  end
  down do
    drop_table(:experiments)
  end
end

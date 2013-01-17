class RemoveNameFromAccounts < ActiveRecord::Migration
  def up
    Account.all.each do |a|
      person = Person.find_by_email(a.email)
      if person
        person.name = "#{a.name} #{a.surname}"
        person.save!
      else
        a.person =
          Person.create({:email => a.email,
                        :name => "#{a.name} #{a.surname}"},
                        :without_protection => true)
        a.save!
      end
    end
    remove_column :accounts, [:name, :surname]
  end

  def down
    raise ActiveRecord::IrreversibleMigration.new
  end
end

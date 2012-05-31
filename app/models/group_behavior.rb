
module GroupBehavior

  def self.extended(klass)
    klass.belongs_to :creator, :class_name => "User", :foreign_key => "user_id"
    # TODO rest of ActiveRecord stuff in here!
  end
   
end
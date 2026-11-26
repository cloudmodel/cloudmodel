require 'base64'
require 'digest'
require 'securerandom'

# A login of the HTTP basic auth in front of a {CloudModel::Services::Nginx}
# service (see Nginx#basic_auth_supported).
#
# Only a hash of the password is stored, written into the guest's htpasswd
# file. The scheme is nginx's own salted SHA-1 (`{SSHA}`), which nginx checks
# itself instead of handing it to the C library's crypt(3), so it works on every
# guest OS. It is a weak hash on purpose: the auth keeps a site out of public
# view (staging, previews), it is not meant to guard secrets.
class CloudModel::Services::Nginx::BasicAuthUser
  include Mongoid::Document
  include Mongoid::Timestamps

  # @!attribute [rw] name
  #   @return [String] login name (no colon, no whitespace — htpasswd format)
  field :name, type: String

  # @!attribute [rw] password_hash
  #   @return [String] `{SSHA}` hash of the password as nginx reads it
  field :password_hash, type: String

  validates :name, presence: true, uniqueness: true, format: { with: /\A[^:\s]+\z/ }
  validates :password, presence: true, if: -> { password_hash.blank? }

  embedded_in :service, class_name: "::CloudModel::Services::Nginx"

  # The clear-text password of the current request; never stored.
  # @return [String, nil]
  attr_reader :password

  # Sets a new password (stored as hash). A blank value keeps the current
  # one, so a form can leave the field empty.
  # @param value [String, nil]
  def password= value
    @password = value
    self.password_hash = self.class.hash_password(value) if value.present?
  end

  # @param password [String]
  # @param salt [String] random bytes, fresh per hash by default
  # @return [String] nginx `{SSHA}` hash: base64(SHA-1(password + salt) + salt)
  def self.hash_password password, salt = SecureRandom.random_bytes(8)
    "{SSHA}#{Base64.strict_encode64(Digest::SHA1.digest(password.to_s + salt) + salt)}"
  end

  # @param password [String]
  # @return [Boolean] whether the password matches the stored hash
  def password_matches? password
    return false unless password_hash.to_s.start_with? '{SSHA}'
    raw = Base64.strict_decode64(password_hash.delete_prefix('{SSHA}'))
    salt = raw[20..]
    ActiveSupport::SecurityUtils.secure_compare(self.class.hash_password(password, salt), password_hash)
  rescue ArgumentError
    false
  end

  # @return [String] the user's line in the htpasswd file
  def htpasswd_line
    "#{name}:#{password_hash}"
  end
end

// EnterpriseActiveAuthInteractor.swift
//
// Copyright (c) 2016 Auth0 (http://auth0.com)
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

import Foundation
import Auth0

struct EnterpriseActiveAuthInteractor: DatabaseAuthenticatable, Loggable {
    
    var identifier: String? = nil

    var email: String? = nil
    var username: String? = nil
    var password: String? = nil

    var validEmail: Bool = false
    var validUsername: Bool = false
    var validPassword: Bool = false

    let usernameValidator: InputValidator = UsernameValidator()
    let emailValidator: InputValidator = EmailValidator()
    let passwordValidator: InputValidator = NonEmptyValidator()

    let authentication: Authentication
    let onAuthentication: (Credentials) -> ()
    let options: Options
    let user: User
    let connection: EnterpriseConnection

    let identifierAttribute: UserAttribute

    init(connection: EnterpriseConnection, authentication: Authentication, user: User, options: Options, callback: @escaping (Credentials) -> ()) {
        self.authentication = authentication
        self.connection = connection
        self.onAuthentication = callback
        self.user = user
        self.options = options

        if !self.options.activeDirectoryEmailAsUsername {
            identifierAttribute = .username
            identifier = self.user.email?.components(separatedBy: "@").first
            _ = updateUsername(identifier)
        } else {
            identifierAttribute = .email
            identifier = self.user.email
            _ = updateEmail(identifier)
        }
    }

    mutating func update(_ attribute: UserAttribute, value: String?) throws {
        let error: Error?

        switch attribute {
        case .email:
            error = updateEmail(value)
        case .username:
            error = updateUsername(value)
        case .password:
            error = updatePassword(value)
        default:
            self.logger.warn("Ignoring unknown input type: \(attribute)")
            return
        }

        if let error = error { throw error }
    }

    private mutating func updateEmail(_ value: String?) -> Error? {
        email = value?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        let error = emailValidator.validate(value)
        validEmail = error == nil
        return error
    }

    private mutating func updateUsername(_ value: String?) -> Error? {
        username = value?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        let error = usernameValidator.validate(value)
        validUsername = error == nil
        return error
    }

    private mutating func updatePassword(_ value: String?) -> Error? {
        password = value
        let error = passwordValidator.validate(value)
        validPassword = error == nil
        return error
    }

    func login(_ callback: @escaping (DatabaseAuthenticatableError?) -> ()) {
        let identifier: String

        if let email = self.email, self.validEmail {
            identifier = email
        } else if let username = self.username, self.validUsername {
            identifier = username
        } else {
            return callback(.nonValidInput)
        }

        guard let password = self.password, self.validPassword else { return callback(.nonValidInput) }

        self.authentication
            .login(
                usernameOrEmail: identifier,
                password: password,
                connection: self.connection.name,
                scope: self.options.scope,
                parameters: self.options.parameters
            )
            .start { self.handleLoginResult($0, callback: callback) }
    }

    private func handleLoginResult(_ result: Auth0.Result<Credentials>, callback: (DatabaseAuthenticatableError?) -> ()) {
        switch result {
        case .failure(let cause as AuthenticationError) where cause.isMultifactorRequired || cause.isMultifactorEnrollRequired:
            self.logger.error("Multifactor is required for user <\(self.identifier)>")
            callback(.multifactorRequired)
        case .failure(let cause as AuthenticationError) where cause.isTooManyAttempts:
            self.logger.error("Blocked user <\(self.identifier)> for too many login attempts")
            callback(.tooManyAttempts)
        case .failure(let cause as AuthenticationError) where cause.isInvalidCredentials:
            self.logger.error("Invalid credentials of user <\(self.identifier)>")
            callback(.invalidEmailPassword)
        case .failure(let cause as AuthenticationError) where cause.isMultifactorCodeInvalid:
            self.logger.error("Multifactor code is invalid for user <\(self.identifier)>")
            callback(.multifactorInvalid)
        case .failure(let cause as AuthenticationError) where cause.isRuleError && cause.description.lowercased() == "user is blocked":
            self.logger.error("Blocked user <\(self.identifier)>")
            callback(.userBlocked)
        case .failure(let cause as AuthenticationError) where cause.code == "password_change_required":
            self.logger.error("Change password required for user <\(self.identifier)>")
            callback(.passwordChangeRequired)
        case .failure(let cause as AuthenticationError) where cause.code == "password_leaked":
            self.logger.error("The password of user <\(self.identifier)> was leaked")
            callback(.passwordLeaked)
        case .failure(let cause):
            self.logger.error("Failed login of user <\(self.identifier)> with error \(cause)")
            callback(.couldNotLogin)
        case .success(let credentials):
            self.logger.info("Authenticated user <\(self.identifier)>")
            callback(nil)
            self.onAuthentication(credentials)
        }
    }

}

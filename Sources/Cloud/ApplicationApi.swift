import HTTP
import Vapor
import Foundation
import Node
import JSON

public let applicationApi = ApplicationApi()

public struct Application: NodeInitializable {
    public let id: UUID
    public let name: String
    public let projectId: UUID
    public let repo: String

    public init(node: Node) throws {
        id = try node.get("id")
        name = try node.get("name")
        projectId = try node.get("project.id")
        repo = try node.get("repoName")
    }
}

extension Application: Equatable {}

public func == (lhs: Application, rhs: Application) -> Bool {
    return lhs.id == rhs.id
        && lhs.name == rhs.name
        && lhs.projectId == rhs.projectId
        && lhs.repo == rhs.repo
}

public final class ApplicationApi {
    // TODO: Make Internal
    public static let base = "https://api.vapor.cloud/application"
    public static let applicationsEndpoint = "\(base)/applications"

    public let hosting = HostingApi()
    public let deploy = DeployApi()
}

extension ApplicationApi {
    public func create(
        for project: Project,
        repo: String,
        name: String,
        with token: Token
    ) throws -> Application {
        let request = try Request(method: .post, uri: ApplicationApi.applicationsEndpoint)
        request.access = token

        var json = JSON([:])
        try json.set("project.id", project.id.uuidString)
        try json.set("repoName", repo)
        try json.set("name", name)
        request.json = json

        let response = try client.respond(to: request)
        return try Application(node: response.json)
    }

    public func get(for project: Project, with token: Token) throws -> [Application] {
        let endpoint = ApplicationApi.applicationsEndpoint + "?projectId=\(project.id.uuidString)"
        let request = try Request(method: .get, uri: endpoint)
        request.access = token

        let response = try client.respond(to: request)
        return try [Application](node: response.json?["data"])
    }

    // TODO: See if we can add call on backend that doesn't require subcalls
    public func all(with token: Token) throws -> [Application] {
        let projects = try adminApi.projects.all(with: token)
        return try projects.flatMap { project in
            return try applicationApi.get(for: project, with: token)
        }
    }
}

public struct Hosting: NodeInitializable {
    public let id: UUID
    public let gitUrl: String
    public let applicationId: UUID

    public init(node: Node) throws {
        id = try node.get("id")
        gitUrl = try node.get("gitUrl")
        applicationId = try node.get("application.id")
    }
}

extension Hosting: Equatable {}

public func == (lhs: Hosting, rhs: Hosting) -> Bool {
    return lhs.id == rhs.id
    && lhs.gitUrl == rhs.gitUrl
    && lhs.applicationId == rhs.applicationId
}

extension ApplicationApi {
    public final class HostingApi {
        public let environments = EnvironmentsApi()

        // TODO: git expects ssh url, ie: git@github.com:vapor/vapor.git
        public func create(for application: Application, git: String, with token: Token) throws -> Hosting {
            let endpoint = applicationsEndpoint.finished(with: "/") + application.repo + "/hosting"
            let request = try Request(method: .post, uri: endpoint)
            request.access = token

            var json = JSON([:])
            try json.set("gitUrl", git)
            request.json = json
            
            let response = try client.respond(to: request)
            return try Hosting(node: response.json)
        }
        
        public func get(for application: Application, with token: Token) throws -> Hosting {
            let endpoint = applicationsEndpoint.finished(with: "/") + application.repo + "/hosting"
            let request = try Request(method: .get, uri: endpoint)
            request.access = token

            let response = try client.respond(to: request)
            return try Hosting(node: response.json)
        }

        public func update(for application: Application, git: String, with token: Token) throws -> Hosting {
            let endpoint = applicationsEndpoint.finished(with: "/") + application.repo + "/hosting"
            let request = try Request(method: .patch, uri: endpoint)
            request.access = token

            var json = JSON([:])
            try json.set("gitUrl", git)
            request.json = json

            let response = try client.respond(to: request)
            return try Hosting(node: response.json)
        }

        // TODO: See if we can get an easier way to do this
        public func all(with token: Token) throws -> [Hosting] {
            let applications = try applicationApi.all(with: token)
            return applications.flatMap { app in
                // TODO: Not all applications have hosting, ask if can return empty array
                return try? applicationApi.hosting.get(for: app, with: token)
            }
        }
    }
}

public struct Environment: NodeInitializable {
    public let applicationId: UUID
    public let branch: String
    public let id: UUID
    public let name: String
    public let running: Bool
    public let replicas: Int

    public init(node: Node) throws {
        // TODO: Full Model?
        applicationId = try node.get("application.id")
        branch = try node.get("defaultBranch")
        id = try node.get("id")
        name = try node.get("name")
        running = try node.get("running")
        replicas = try node.get("replicas")
    }
}

extension ApplicationApi.HostingApi {
    public final class EnvironmentsApi {
        public func create(
            for application: Application,
            name: String,
            branch: String,
            with token: Token
        ) throws -> Environment {
            let endpoint = ApplicationApi.applicationsEndpoint.finished(with: "/") + application.repo + "/hosting/environments"
            let request = try Request(method: .post, uri: endpoint)
            request.access = token

            var json = JSON([:])
            try json.set("name", name)
            try json.set("defaultBranch", branch)
            request.json = json

            let response = try client.respond(to: request)
            return try Environment(node: response.json)
        }

        public func all(for application: Application, with token: Token) throws -> [Environment] {
            let endpoint = ApplicationApi.applicationsEndpoint.finished(with: "/") + application.repo + "/hosting/environments"
            let request = try Request(method: .get, uri: endpoint)
            request.access = token

            let response = try client.respond(to: request)
            return try [Environment](node: response.json)
        }
    }
}

public struct Deploy: NodeInitializable {
    public let application: Application
    public let defaultBranch: String
    // TODO: Rename deployOperations or operations
    public let deployments: [Deployment]
    public let id: UUID
    public let name: String
    public let replicas: Int
    public let running: Bool

    public init(node: Node) throws {
        application = try node.get("application")
        defaultBranch = try node.get("defaultBranch")
        deployments = try node.get("deployments")
        id = try node.get("id")
        name = try node.get("name")
        replicas = try node.get("replicas")
        running = try node.get("running")
    }
}

public struct Git: NodeInitializable {
    public let branch: String
    public let url: String

    public init(node: Node) throws {
        branch = try node.get("branch")
        url = try node.get("url")
    }
}

public enum DeployType: String, NodeInitializable {
    case scale, code

    public init(node: Node) throws {
        guard
            let string = node.string,
            let new = DeployType(rawValue: string)
            else {
                throw NodeError.unableToConvert(input: node, expectation: "String", path: [])
        }
        self = new
    }
}

// TODO: Rename, DeployOperation
public struct Deployment: NodeInitializable {
    public let repo: String
    public let environment: String
    public let git: Git
    public let id: UUID
    public let replicas: Int
    public let status: String
    public let version: String
    public let domains: [String]
    public let type: DeployType

    public init(node: Node) throws {
        repo = try node.get("environment.application.repoName")
        environment = try node.get("environment.name")
        git = try node.get("git")
        id = try node.get("id")
        replicas = try node.get("replicas")
        status = try node.get("status")
        type = try node.get("type.name")
        version = try node.get("version")
        domains = try node.get("domains")
    }

}

//{
//    "application":{
//        "id":"2B4C22C7-3797-46DF-AC21-4A46D24E7494",
//        "name":"test-1490986172",
//        "project":{
//            "id":"8CF0C5B1-E8B6-4E70-A125-6C188B4CA41F"
//        },
//        "repoName":"test-1490986172"
//    },
//    "defaultBranch":"master",
//    "deployments":[
//    {
//    "databaseCredentials":{
//    "password":"WtJI2lKWRgxkE\/v7LoTJERZ1G",
//    "username":"\/VEY\/BQlzrFK7eQ"
//    },
//    "domains":[
//
//    ],
//    "environment":{
//    "application":{
//    "repoName":"test-1490986172"
//    },
//    "name":"staging"
//    },
//    "git":{
//    "branch":"master",
//    "url":"git@github.com:vapor\/light-template.git"
//    },
//    "id":"736163E9-23D7-45D8-88E9-0999EBECEFCD",
//    "replicas":1,
//    "status":"working",
//    "type":{
//    "name":"scale"
//    },
//    "version":1
//    },
//    {
//    "databaseCredentials":{
//    "password":"WtJI2lKWRgxkE\/v7LoTJERZ1G",
//    "username":"\/VEY\/BQlzrFK7eQ"
//    },
//    "domains":[
//
//    ],
//    "environment":{
//    "application":{
//    "repoName":"test-1490986172"
//    },
//    "name":"staging"
//    },
//    "git":{
//    "branch":"master",
//    "url":"git@github.com:vapor\/light-template.git"
//    },
//    "id":"0DEE45F3-BA41-49D0-84B4-1A52AFC95B2F",
//    "replicas":1,
//    "status":"working",
//    "type":{
//    "method":"incremental",
//    "name":"code"
//    },
//    "version":2
//    }
//    ],
//    "id":"F31CDE3F-291B-4591-B441-2F6910049846",
//    "name":"staging",
//    "replicas":1,
//    "running":true
//}

public enum BuildType: String {
    case clean, incremental
}

extension ApplicationApi {
    public final class DeployApi {
        //gitBranch (String) (Optional) What branch should be deployed code (String) (Required) Should be incremental or clean
        public func deploy(
            for app: Application,
            env: Environment,
            code: BuildType,
            with token: Token
        ) throws -> Deploy {
            let endpoint = ApplicationApi.applicationsEndpoint.finished(with: "/")
                + app.repo
                + "/hosting/environments/"
                + env.name
            let request = try Request(method: .patch, uri: endpoint)
            request.access = token

            var json = JSON([:])
            try json.set("code", code.rawValue)
            request.json = json
            
            let response = try client.respond(to: request)
            return try Deploy(node: response.json)
        }

        public func scale(for app: Application, env: Environment, replicas: Int, with token: Token) throws {
            let endpoint = ApplicationApi.applicationsEndpoint.finished(with: "/")
                + app.repo
                + "/hosting/environments/"
                + env.name
            let request = try Request(method: .patch, uri: endpoint)
            request.access = token

            var json = JSON([:])
            try json.set("replicas", replicas)
            request.json = json
        }
    }
}

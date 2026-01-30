//
//  ContentView.swift
//  SCOTSMAN
//
//  Created by Ian Miller on 1/27/26.
//

import SwiftUI
import CoreData
import Combine
import UIKit



struct ContentView: View {
    
    
    @State private var isShowingSettings = false
    @State private var isAuthenticating = false
    
    var body: some View {
        TabView {
            NavigationStack {
                CompaniesView()
                    .navigationTitle("Companies")
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button {
                                isShowingSettings = true
                            } label: {
                                Image(systemName: "gearshape")
                            }
                        }
                    }
            }
            .tabItem {
                Label("Companies", systemImage: "building.2")
            }
            
            NavigationStack {
                ContactsView()
                    .navigationTitle("Contacts")
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button {
                                isShowingSettings = true
                            } label: {
                                Image(systemName: "gearshape")
                            }
                        }
                    }
            }
            .tabItem {
                Label("Contacts", systemImage: "person.2")
            }
            
            NavigationStack {
                OpportunitiesView()
                    .navigationTitle("Opportunities")
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button {
                                isShowingSettings = true
                            } label: {
                                Image(systemName: "gearshape")
                            }
                        }
                    }
            }
            .tabItem {
                Label("Opportunities", systemImage: "chart.bar")
            }
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsView()
        }
    }
}


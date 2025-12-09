import { useState } from "react";
import { useNavigate } from "react-router-dom";
import { Header } from "@/components/shared/Header";
import { ClientNav } from "@/components/shared/MobileNav";
import { Avatar } from "@/components/shared/Avatar";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { familyMembers } from "@/data/mockData";
import { 
  User, MapPin, Users, Phone, CreditCard, Settings, 
  HelpCircle, FileText, Shield, LogOut, ChevronRight, 
  Plus, Edit, Home, Building, TreePine
} from "lucide-react";

const ClientProfile = () => {
  const navigate = useNavigate();
  const handleSOS = () => navigate("/client/sos");

  const addresses = [
    { id: "1", label: "Home", name: "Main Residence", address: "123 Jalan Merdeka, KL", isDefault: true, icon: Home },
    { id: "2", label: "Parents", name: "Parents House", address: "456 Jalan Kampung, Selangor", isDefault: false, icon: Users },
    { id: "3", label: "Kampung", name: "Grandmother's House", address: "789 Kampung Baru, Pahang", isDefault: false, icon: TreePine },
  ];

  const emergencyContacts = [
    { id: "1", name: "Ahmad (Brother)", phone: "+60 12-345 6789", relationship: "Sibling" },
    { id: "2", name: "Dr. Tan", phone: "+60 3-8765 4321", relationship: "Family Doctor" },
  ];

  const menuItems = [
    { icon: User, label: "Edit Profile", path: "/client/profile/edit" },
    { icon: MapPin, label: "Family Addresses", path: "/client/profile/addresses", count: addresses.length },
    { icon: Users, label: "Family Members", path: "/client/profile/family", count: familyMembers.length },
    { icon: Phone, label: "Emergency Contacts", path: "/client/profile/emergency", count: emergencyContacts.length },
    { icon: CreditCard, label: "Payments & Billing", path: "/client/profile/payments" },
  ];

  const settingsItems = [
    { icon: HelpCircle, label: "Help Center" },
    { icon: FileText, label: "FAQ" },
    { icon: Shield, label: "Privacy Policy" },
    { icon: FileText, label: "Terms of Service" },
  ];

  return (
    <div className="min-h-screen bg-background pb-24">
      <Header title="Account" showNotification={false} />

      <main className="px-4 py-4 space-y-6">
        {/* Profile Header */}
        <Card variant="default" padding="sm">
          <div className="flex items-center gap-4">
            <Avatar
              src="https://images.unsplash.com/photo-1438761681033-6461ffad8d80?w=100&h=100&fit=crop&crop=face"
              name="Aisha Rahman"
              size="xl"
              showBorder
            />
            <div className="flex-1">
              <h2 className="text-xl font-bold text-foreground">Aisha Rahman</h2>
              <p className="text-muted-foreground">+60 12-345 6789</p>
              <p className="text-sm text-muted-foreground">aisha@email.com</p>
            </div>
          </div>
          <Button variant="outline" size="full" className="mt-4">
            <Edit className="h-4 w-4 mr-2" />
            Edit Profile
          </Button>
        </Card>

        {/* Quick Stats */}
        <div className="grid grid-cols-3 gap-3">
          <Card variant="action" padding="sm" className="text-center">
            <p className="text-2xl font-bold text-primary">12</p>
            <p className="text-xs text-muted-foreground">Bookings</p>
          </Card>
          <Card variant="action" padding="sm" className="text-center">
            <p className="text-2xl font-bold text-primary">3</p>
            <p className="text-xs text-muted-foreground">Caregivers</p>
          </Card>
          <Card variant="action" padding="sm" className="text-center">
            <p className="text-2xl font-bold text-primary">{familyMembers.length}</p>
            <p className="text-xs text-muted-foreground">Family</p>
          </Card>
        </div>

        {/* Family Addresses Preview */}
        <section>
          <div className="flex items-center justify-between mb-3">
            <h3 className="font-semibold text-foreground">Family Addresses</h3>
            <Button variant="ghost" size="sm" className="text-primary">
              <Plus className="h-4 w-4 mr-1" />
              Add
            </Button>
          </div>
          <div className="space-y-2">
            {addresses.slice(0, 2).map((addr) => (
              <Card key={addr.id} variant="outline" padding="sm" className="flex items-center gap-3">
                <div className="w-10 h-10 bg-primary/10 rounded-lg flex items-center justify-center">
                  <addr.icon className="h-5 w-5 text-primary" />
                </div>
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2">
                    <p className="font-medium text-foreground">{addr.name}</p>
                    {addr.isDefault && <Badge variant="match" className="text-[10px]">Default</Badge>}
                  </div>
                  <p className="text-sm text-muted-foreground truncate">{addr.address}</p>
                </div>
                <ChevronRight className="h-5 w-5 text-muted-foreground shrink-0" />
              </Card>
            ))}
          </div>
        </section>

        {/* Emergency Contacts Preview */}
        <section>
          <div className="flex items-center justify-between mb-3">
            <h3 className="font-semibold text-foreground">Emergency Contacts</h3>
            <Button variant="ghost" size="sm" className="text-primary">
              <Plus className="h-4 w-4 mr-1" />
              Add
            </Button>
          </div>
          <div className="space-y-2">
            {emergencyContacts.map((contact) => (
              <Card key={contact.id} variant="outline" padding="sm" className="flex items-center gap-3">
                <Avatar name={contact.name} size="md" />
                <div className="flex-1">
                  <p className="font-medium text-foreground">{contact.name}</p>
                  <p className="text-sm text-muted-foreground">{contact.phone}</p>
                </div>
                <Badge variant="secondary" className="text-[10px]">{contact.relationship}</Badge>
              </Card>
            ))}
          </div>
        </section>

        {/* Menu Items */}
        <section>
          <h3 className="font-semibold text-foreground mb-3">Account</h3>
          <Card variant="default" padding="none">
            {menuItems.map((item, index) => (
              <button
                key={item.label}
                className={`w-full flex items-center gap-4 px-4 py-4 hover:bg-muted/50 transition-colors ${
                  index !== menuItems.length - 1 ? "border-b border-border" : ""
                }`}
              >
                <item.icon className="h-5 w-5 text-primary" />
                <span className="flex-1 text-left font-medium text-foreground">{item.label}</span>
                {item.count && (
                  <Badge variant="secondary">{item.count}</Badge>
                )}
                <ChevronRight className="h-5 w-5 text-muted-foreground" />
              </button>
            ))}
          </Card>
        </section>

        {/* Settings */}
        <section>
          <h3 className="font-semibold text-foreground mb-3">Support & Settings</h3>
          <Card variant="default" padding="none">
            {settingsItems.map((item, index) => (
              <button
                key={item.label}
                className={`w-full flex items-center gap-4 px-4 py-4 hover:bg-muted/50 transition-colors ${
                  index !== settingsItems.length - 1 ? "border-b border-border" : ""
                }`}
              >
                <item.icon className="h-5 w-5 text-muted-foreground" />
                <span className="flex-1 text-left font-medium text-foreground">{item.label}</span>
                <ChevronRight className="h-5 w-5 text-muted-foreground" />
              </button>
            ))}
          </Card>
        </section>

        {/* Logout */}
        <Button variant="emergency" size="full">
          <LogOut className="h-5 w-5 mr-2" />
          Logout
        </Button>
      </main>

      <ClientNav onSOS={handleSOS} />
    </div>
  );
};

export default ClientProfile;

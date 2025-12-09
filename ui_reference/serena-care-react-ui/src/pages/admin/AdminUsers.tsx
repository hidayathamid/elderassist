import { useState } from "react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Badge } from "@/components/ui/badge";
import { Avatar } from "@/components/shared/Avatar";
import { StatusBadge } from "@/components/shared/StatusBadge";
import { BottomSheet } from "@/components/shared/BottomSheet";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { familyMembers } from "@/data/mockData";
import { Search, Filter, Eye, Edit, MoreVertical, Mail, Phone, MapPin, Calendar } from "lucide-react";

const AdminUsers = () => {
  const [searchQuery, setSearchQuery] = useState("");
  const [selectedUser, setSelectedUser] = useState<any>(null);

  const users = [
    {
      id: "1",
      name: "Aisha Rahman",
      email: "aisha@email.com",
      phone: "+60 12-345 6789",
      photo: "https://images.unsplash.com/photo-1438761681033-6461ffad8d80?w=100&h=100&fit=crop&crop=face",
      status: "active",
      totalBookings: 12,
      joinDate: "2024-01-15",
      familyMembers: 3,
    },
    {
      id: "2",
      name: "Ahmad Ibrahim",
      email: "ahmad@email.com",
      phone: "+60 12-987 6543",
      photo: "https://images.unsplash.com/photo-1566616213894-2d4e1baee5d8?w=100&h=100&fit=crop&crop=face",
      status: "active",
      totalBookings: 8,
      joinDate: "2024-02-20",
      familyMembers: 2,
    },
    {
      id: "3",
      name: "Siti Aminah",
      email: "siti@email.com",
      phone: "+60 11-222 3333",
      photo: "https://images.unsplash.com/photo-1544005313-94ddf0286df2?w=100&h=100&fit=crop&crop=face",
      status: "inactive",
      totalBookings: 3,
      joinDate: "2024-03-10",
      familyMembers: 1,
    },
  ];

  const filteredUsers = users.filter(user =>
    user.name.toLowerCase().includes(searchQuery.toLowerCase()) ||
    user.email.toLowerCase().includes(searchQuery.toLowerCase())
  );

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-foreground">Users</h1>
          <p className="text-muted-foreground">Manage registered users and their accounts</p>
        </div>
        <Button>Add User</Button>
      </div>

      {/* Stats */}
      <div className="grid grid-cols-4 gap-4">
        <Card variant="default" padding="sm">
          <p className="text-2xl font-bold text-foreground">1,250</p>
          <p className="text-sm text-muted-foreground">Total Users</p>
        </Card>
        <Card variant="default" padding="sm">
          <p className="text-2xl font-bold text-success">1,180</p>
          <p className="text-sm text-muted-foreground">Active</p>
        </Card>
        <Card variant="default" padding="sm">
          <p className="text-2xl font-bold text-warning">45</p>
          <p className="text-sm text-muted-foreground">New This Month</p>
        </Card>
        <Card variant="default" padding="sm">
          <p className="text-2xl font-bold text-muted-foreground">25</p>
          <p className="text-sm text-muted-foreground">Inactive</p>
        </Card>
      </div>

      {/* Search and Filters */}
      <Card variant="default" padding="sm">
        <div className="flex items-center gap-4">
          <div className="relative flex-1">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
            <Input
              placeholder="Search by name or email..."
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              className="pl-10"
            />
          </div>
          <Button variant="outline">
            <Filter className="h-4 w-4 mr-2" />
            Filters
          </Button>
        </div>
      </Card>

      {/* Users Table */}
      <Card variant="default" padding="none">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>User</TableHead>
              <TableHead>Contact</TableHead>
              <TableHead>Status</TableHead>
              <TableHead>Bookings</TableHead>
              <TableHead>Family</TableHead>
              <TableHead>Joined</TableHead>
              <TableHead className="text-right">Actions</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {filteredUsers.map((user) => (
              <TableRow key={user.id}>
                <TableCell>
                  <div className="flex items-center gap-3">
                    <Avatar src={user.photo} name={user.name} size="sm" />
                    <div>
                      <p className="font-medium text-foreground">{user.name}</p>
                      <p className="text-xs text-muted-foreground">{user.email}</p>
                    </div>
                  </div>
                </TableCell>
                <TableCell>
                  <p className="text-sm text-muted-foreground">{user.phone}</p>
                </TableCell>
                <TableCell>
                  <StatusBadge status={user.status === "active" ? "online" : "offline"} />
                </TableCell>
                <TableCell>
                  <span className="font-medium">{user.totalBookings}</span>
                </TableCell>
                <TableCell>
                  <Badge variant="secondary">{user.familyMembers} members</Badge>
                </TableCell>
                <TableCell>
                  <span className="text-sm text-muted-foreground">{user.joinDate}</span>
                </TableCell>
                <TableCell className="text-right">
                  <div className="flex items-center justify-end gap-2">
                    <Button variant="ghost" size="iconSm" onClick={() => setSelectedUser(user)}>
                      <Eye className="h-4 w-4" />
                    </Button>
                    <Button variant="ghost" size="iconSm">
                      <Edit className="h-4 w-4" />
                    </Button>
                    <Button variant="ghost" size="iconSm">
                      <MoreVertical className="h-4 w-4" />
                    </Button>
                  </div>
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </Card>

      {/* User Details Sheet */}
      <BottomSheet
        open={!!selectedUser}
        onClose={() => setSelectedUser(null)}
        title="User Details"
        height="full"
      >
        {selectedUser && (
          <div className="space-y-6">
            {/* Profile */}
            <div className="flex items-center gap-4">
              <Avatar src={selectedUser.photo} name={selectedUser.name} size="xl" />
              <div>
                <h3 className="text-xl font-bold text-foreground">{selectedUser.name}</h3>
                <StatusBadge status={selectedUser.status === "active" ? "online" : "offline"} />
              </div>
            </div>

            {/* Contact Info */}
            <Card variant="outline" padding="sm">
              <h4 className="font-semibold text-foreground mb-3">Contact Information</h4>
              <div className="space-y-2">
                <div className="flex items-center gap-3">
                  <Mail className="h-4 w-4 text-muted-foreground" />
                  <span className="text-sm">{selectedUser.email}</span>
                </div>
                <div className="flex items-center gap-3">
                  <Phone className="h-4 w-4 text-muted-foreground" />
                  <span className="text-sm">{selectedUser.phone}</span>
                </div>
                <div className="flex items-center gap-3">
                  <Calendar className="h-4 w-4 text-muted-foreground" />
                  <span className="text-sm">Joined {selectedUser.joinDate}</span>
                </div>
              </div>
            </Card>

            {/* Family Members */}
            <div>
              <h4 className="font-semibold text-foreground mb-3">Family Members</h4>
              <div className="space-y-2">
                {familyMembers.map((member) => (
                  <Card key={member.id} variant="outline" padding="sm">
                    <div className="flex items-center gap-3">
                      <Avatar src={member.photo} name={member.name} size="sm" />
                      <div className="flex-1">
                        <p className="font-medium text-foreground">{member.name}</p>
                        <p className="text-xs text-muted-foreground">{member.age} years old</p>
                      </div>
                      <div className="flex gap-1">
                        {member.conditions.map((c) => (
                          <Badge key={c} variant="secondary" className="text-[10px]">{c}</Badge>
                        ))}
                      </div>
                    </div>
                  </Card>
                ))}
              </div>
            </div>

            {/* Actions */}
            <div className="flex gap-3">
              <Button variant="outline" className="flex-1">Reset Password</Button>
              <Button variant="emergency" className="flex-1">Suspend Account</Button>
            </div>
          </div>
        )}
      </BottomSheet>
    </div>
  );
};

export default AdminUsers;

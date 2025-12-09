import { useState } from "react";
import { Header } from "@/components/shared/Header";
import { CaregiverNav } from "@/components/shared/MobileNav";
import { Avatar } from "@/components/shared/Avatar";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { chatMessages, familyMembers } from "@/data/mockData";
import { Send, Phone, MoreVertical } from "lucide-react";

const CaregiverChat = () => {
  const [selectedChat, setSelectedChat] = useState<string | null>(null);
  const [message, setMessage] = useState("");

  const chatList = [
    {
      id: "1",
      user: familyMembers[0],
      lastMessage: "Thank you for today!",
      time: "10:34 AM",
      unread: 2,
    },
    {
      id: "2",
      user: familyMembers[1],
      lastMessage: "See you tomorrow",
      time: "Yesterday",
      unread: 0,
    },
    {
      id: "3",
      user: familyMembers[2],
      lastMessage: "The medication has been administered",
      time: "Mon",
      unread: 0,
    },
  ];

  const handleSendMessage = () => {
    if (message.trim()) {
      // In real app, would send message
      setMessage("");
    }
  };

  if (selectedChat) {
    const chat = chatList.find(c => c.id === selectedChat);
    
    return (
      <div className="min-h-screen bg-background flex flex-col">
        {/* Chat Header */}
        <header className="sticky top-0 z-40 bg-card border-b border-border">
          <div className="flex items-center justify-between h-16 px-4">
            <div className="flex items-center gap-3">
              <Button variant="ghost" size="iconSm" onClick={() => setSelectedChat(null)}>
                ←
              </Button>
              <Avatar src={chat?.user.photo} name={chat?.user.name || ""} size="sm" status="online" />
              <div>
                <h3 className="font-semibold text-foreground">{chat?.user.name}</h3>
                <p className="text-xs text-success">Online</p>
              </div>
            </div>
            <div className="flex items-center gap-2">
              <Button variant="ghost" size="iconSm">
                <Phone className="h-5 w-5" />
              </Button>
              <Button variant="ghost" size="iconSm">
                <MoreVertical className="h-5 w-5" />
              </Button>
            </div>
          </div>
        </header>

        {/* Messages */}
        <div className="flex-1 overflow-y-auto p-4 space-y-4">
          {chatMessages.map((msg) => (
            <div
              key={msg.id}
              className={`flex ${msg.sender === "caregiver" ? "justify-end" : "justify-start"}`}
            >
              <div
                className={`max-w-[75%] rounded-2xl px-4 py-2 ${
                  msg.sender === "caregiver"
                    ? "bg-muted text-foreground rounded-br-sm"
                    : "bg-primary text-primary-foreground rounded-bl-sm"
                }`}
              >
                <p className="text-sm">{msg.message}</p>
                <p className={`text-[10px] mt-1 ${
                  msg.sender === "caregiver" ? "text-muted-foreground" : "text-primary-foreground/70"
                }`}>
                  {msg.time}
                </p>
              </div>
            </div>
          ))}
        </div>

        {/* Input */}
        <div className="sticky bottom-0 bg-card border-t border-border p-4">
          <div className="flex items-center gap-3">
            <Input
              value={message}
              onChange={(e) => setMessage(e.target.value)}
              placeholder="Type a message..."
              className="flex-1"
              onKeyDown={(e) => e.key === "Enter" && handleSendMessage()}
            />
            <Button size="icon" onClick={handleSendMessage} disabled={!message.trim()}>
              <Send className="h-5 w-5" />
            </Button>
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-background pb-24">
      <Header title="Chat" showNotification notificationCount={2} />

      <main className="px-4 py-4">
        <div className="space-y-2">
          {chatList.map((chat) => (
            <Card
              key={chat.id}
              variant="action"
              padding="sm"
              onClick={() => setSelectedChat(chat.id)}
            >
              <div className="flex items-center gap-3">
                <Avatar src={chat.user.photo} name={chat.user.name} size="md" status="online" />
                <div className="flex-1 min-w-0">
                  <div className="flex items-center justify-between">
                    <h4 className="font-semibold text-foreground">{chat.user.name}</h4>
                    <span className="text-xs text-muted-foreground">{chat.time}</span>
                  </div>
                  <div className="flex items-center justify-between mt-1">
                    <p className="text-sm text-muted-foreground truncate">{chat.lastMessage}</p>
                    {chat.unread > 0 && (
                      <span className="w-5 h-5 bg-primary rounded-full flex items-center justify-center text-[10px] text-primary-foreground font-bold">
                        {chat.unread}
                      </span>
                    )}
                  </div>
                </div>
              </div>
            </Card>
          ))}
        </div>
      </main>

      <CaregiverNav />
    </div>
  );
};

export default CaregiverChat;
